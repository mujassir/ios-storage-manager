import Foundation
import SwiftData
import BackgroundTasks
import UserNotifications
import Observation

/// Runs auto-move rules (Pro).
///
/// - In the background: a `BGProcessingTask` that only runs while charging and online uploads matching
///   videos. Originals are *not* deleted there, because iOS needs the user to confirm deletions.
///   A notification then invites the user to free the space with one tap.
/// - In the foreground: the dashboard shows what the rules would move, with a "Move now" button.
@Observable
final class AutoMoveService {
    private static let rulesKey = "automove.rules"

    private(set) var rules: [AutoMoveRule] = []
    private(set) var lastRun: Date?
    private(set) var lastRunMessage: String?

    @ObservationIgnored private let photos: PhotoLibraryService
    @ObservationIgnored private let transfers: TransferEngine
    @ObservationIgnored private let store: ProStore
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let defaults = SharedContainer.defaults

    init(photos: PhotoLibraryService, transfers: TransferEngine, store: ProStore, container: ModelContainer) {
        self.photos = photos
        self.transfers = transfers
        self.store = store
        self.container = container
        if let data = defaults.data(forKey: Self.rulesKey),
           let saved = try? JSONDecoder().decode([AutoMoveRule].self, from: data) {
            rules = saved
        }
        lastRun = defaults.object(forKey: "automove.lastRun") as? Date
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: AppConfig.autoMoveTaskIdentifier, using: .main) { @Sendable [weak self] task in
            let box = UncheckedSendableBox(task)
            MainActor.assumeIsolated { self?.handle(box.value) }
        }
    }

    var hasEnabledRules: Bool { rules.contains(where: \.isEnabled) }

    // MARK: Editing

    func save(_ rule: AutoMoveRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        persist()
    }

    func delete(_ rule: AutoMoveRule) {
        rules.removeAll { $0.id == rule.id }
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(rules), forKey: Self.rulesKey)
        if hasEnabledRules {
            Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
            schedule()
        } else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: AppConfig.autoMoveTaskIdentifier)
        }
    }

    // MARK: Planning

    func plan(for videos: [VideoAsset]) -> [AutoMoveRule.Destination: [VideoAsset]] {
        AutoMoveRule.plan(rules, videos: videos, excluding: idsAlreadyInCloud())
    }

    private func idsAlreadyInCloud() -> Set<String> {
        let entries = (try? container.mainContext.fetch(FetchDescriptor<MovedVideo>())) ?? []
        return Set(entries.filter(\.isVerified).map(\.originalAssetIdentifier))
    }

    static func engineDestination(_ destination: AutoMoveRule.Destination) -> TransferEngine.Destination {
        switch destination {
        case .automatic: .automatic
        case .account(let key): .account(key)
        }
    }

    // MARK: Background

    /// Asks iOS to run the rules the next time the phone is charging and online (usually overnight).
    func schedule() {
        guard store.isPro, hasEnabledRules else { return }
        let request = BGProcessingTaskRequest(identifier: AppConfig.autoMoveTaskIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date.now.addingTimeInterval(60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handle(_ task: BGTask) {
        let work = Task { await self.runRules() }
        task.expirationHandler = { @Sendable in work.cancel() }
        Task {
            let success = await work.value
            task.setTaskCompleted(success: success)
            schedule()
        }
    }

    /// Uploads everything the rules match (without deleting originals). Returns false if it was cut short.
    @discardableResult
    func runRules() async -> Bool {
        guard store.isPro, hasEnabledRules, !transfers.isRunning else { return true }
        guard let videos = try? await photos.scanVideos() else { return false }
        let plan = plan(for: videos)
        guard !plan.isEmpty else { return true }

        var moved = 0
        var bytes: Int64 = 0
        for (destination, batch) in plan {
            if Task.isCancelled { break }
            guard let summary = await transfers.runToCompletion(batch, destination: Self.engineDestination(destination), context: container.mainContext) else { continue }
            moved += summary.movedCount
            let movedIDs = Set(transfers.jobs.filter { $0.state == .moved }.map(\.video.id))
            bytes += batch.filter { movedIDs.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
            transfers.dismiss()
        }

        lastRun = .now
        defaults.set(lastRun, forKey: "automove.lastRun")
        lastRunMessage = moved > 0 ? "Backed up \(moved) videos (\(ByteFormatting.string(bytes)))." : "Nothing new to move."
        if moved > 0 { await notifyReadyToFree(count: moved, bytes: bytes) }
        return !Task.isCancelled
    }

    private func notifyReadyToFree(count: Int, bytes: Int64) async {
        let content = UNMutableNotificationContent()
        content.title = "\(count) video\(count == 1 ? "" : "s") backed up"
        content.body = "They're safe in your cloud. Open Storage Manager to free \(ByteFormatting.string(bytes)) on your iPhone."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "automove.done", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
