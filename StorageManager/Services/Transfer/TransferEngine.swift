import Foundation
import SwiftData
import UIKit
import Observation

/// Moves videos from Photos to the user's clouds:
/// export original → analyze (thumbnail, Vision, Apple Intelligence title) → upload → verify → catalog
/// → one batch delete from Photos → update each account's manifest.
///
/// Safety rule: a video is only deleted from the phone if the cloud reports the same size and checksum
/// as the exported original.
@Observable
final class TransferEngine {
    enum Destination: Hashable {
        case automatic
        case account(AccountKey)

        var preferredAccount: AccountKey? {
            if case .account(let key) = self { return key }
            return nil
        }
    }

    enum JobState: Equatable {
        case waiting
        case preparing(Double)
        case analyzing
        case uploading(Double)
        case verifying
        case moved
        /// Uploaded, but the cloud copy couldn't be verified, so the original stays on the phone.
        case keptOnPhone(String)
        case failed(String)
        case cancelled

        var isKeptOnPhone: Bool { if case .keptOnPhone = self { return true } else { return false } }
        var isFailed: Bool { if case .failed = self { return true } else { return false } }

        var isFinished: Bool {
            switch self {
            case .moved, .keptOnPhone, .failed, .cancelled: true
            default: false
            }
        }

        var label: String {
            switch self {
            case .waiting: "Waiting"
            case .preparing(let p): p > 0 ? "Downloading from iCloud \(Int(p * 100))%" : "Preparing"
            case .analyzing: "Analyzing"
            case .uploading(let p): "Uploading \(Int(p * 100))%"
            case .verifying: "Verifying"
            case .moved: "Moved"
            case .keptOnPhone: "Uploaded · kept on phone"
            case .failed(let message): message
            case .cancelled: "Cancelled"
            }
        }
    }

    struct Job: Identifiable {
        let video: VideoAsset
        var state: JobState = .waiting
        var account: AccountKey?
        var uploadedBytes: Int64 = 0
        var id: String { video.id }
    }

    struct Summary: Equatable {
        var movedCount = 0
        var keptCount = 0
        var failedCount = 0
        var freedBytes: Int64 = 0
        var deletedFromPhone = false
        var deletionDeclined = false
    }

    private(set) var jobs: [Job] = []
    private(set) var isRunning = false
    private(set) var isWaitingToDelete = false
    private(set) var summary: Summary?
    private(set) var isPausedForLowPower = false

    @ObservationIgnored private let photos: PhotoLibraryService
    @ObservationIgnored private let accounts: AccountManager
    @ObservationIgnored private let insights: VideoInsightService
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let background: ContinuedProcessingCoordinator
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var reportsBackgroundProgress = true

    init(photos: PhotoLibraryService, accounts: AccountManager, insights: VideoInsightService,
         settings: AppSettings, background: ContinuedProcessingCoordinator) {
        self.photos = photos
        self.accounts = accounts
        self.insights = insights
        self.settings = settings
        self.background = background
    }

    var totalBytes: Int64 { jobs.reduce(0) { $0 + $1.video.sizeBytes } }
    var completedBytes: Int64 { jobs.reduce(0) { $0 + ($1.state.isFinished ? $1.video.sizeBytes : $1.uploadedBytes) } }
    var fractionCompleted: Double { totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0 }
    var finishedCount: Int { jobs.filter { $0.state.isFinished }.count }
    var hasActivity: Bool { isRunning || summary != nil }

    // MARK: Control

    func start(_ videos: [VideoAsset], destination: Destination, deleteAfterMove: Bool, context: ModelContext) {
        guard !isRunning, !videos.isEmpty else { return }
        prepare(videos)
        runTask = Task { [weak self] in
            await self?.run(destination: destination, deleteAfterMove: deleteAfterMove, showsSystemProgress: true, context: context)
        }
    }

    /// Runs a batch to completion and returns its summary. Used by auto-move rules in a background task,
    /// where originals are not deleted (that needs the user's confirmation in the foreground).
    func runToCompletion(_ videos: [VideoAsset], destination: Destination, context: ModelContext) async -> Summary? {
        guard !isRunning, !videos.isEmpty else { return nil }
        prepare(videos)
        let task = Task { [weak self] in
            await self?.run(destination: destination, deleteAfterMove: false, showsSystemProgress: false, context: context)
        }
        runTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        return summary
    }

    private func prepare(_ videos: [VideoAsset]) {
        jobs = videos.map { Job(video: $0) }
        summary = nil
        isRunning = true
    }

    /// Deletes originals that are already verified in the cloud but still on the phone
    /// (from auto-move, or a move where deletion wasn't confirmed). One iOS confirmation for all.
    func freeUpVerifiedOriginals(context: ModelContext, onDevice videos: [VideoAsset]) async throws -> Int64 {
        let local = Dictionary(videos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pending = ((try? context.fetch(FetchDescriptor<MovedVideo>())) ?? []).filter { $0.isPendingCleanup && local[$0.originalAssetIdentifier] != nil }
        guard !pending.isEmpty else { return 0 }
        try await photos.deleteVideos(withIdentifiers: pending.map(\.originalAssetIdentifier))
        for entry in pending { entry.deletedFromDevice = true }
        try context.save()
        return pending.reduce(0) { total, entry in
            total + ((local[entry.originalAssetIdentifier]?.isLocallyAvailable ?? false) ? entry.sizeBytes : 0)
        }
    }

    func cancel() {
        runTask?.cancel()
    }

    /// Clears the finished batch from the screen.
    func dismiss() {
        guard !isRunning else { return }
        jobs = []
        summary = nil
    }

    // MARK: Batch

    private func run(destination: Destination, deleteAfterMove: Bool, showsSystemProgress: Bool, context: ModelContext) async {
        let count = jobs.count
        reportsBackgroundProgress = showsSystemProgress
        if showsSystemProgress {
            background.begin(title: "Moving \(count) video\(count == 1 ? "" : "s")", subtitle: "Starting…") { [weak self] in
                self?.cancel()
            }
        }
        // Videos already verified in the cloud are not uploaded again.
        let alreadyInCloud = Dictionary(
            ((try? context.fetch(FetchDescriptor<MovedVideo>())) ?? [])
                .filter { $0.isVerified && !$0.originalAssetIdentifier.isEmpty }
                .map { ($0.originalAssetIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let linked = (try? context.fetch(FetchDescriptor<LinkedAccount>())) ?? []
        let connected = linked.filter { accounts.isConnected($0) }
        await accounts.refreshAllQuotas(connected)
        var allocator = StorageAllocator(freeBytes: Dictionary(
            connected.compactMap { account in accounts.quota(for: account).map { (account.accountKey, $0.freeBytes) } },
            uniquingKeysWith: { first, _ in first }
        ))
        let preferred = destination.preferredAccount

        let workDirectory = FileManager.default.temporaryDirectory.appending(path: "Transfers/\(UUID().uuidString)")
        var movedEntries: [MovedVideo] = []
        var touchedAccounts: Set<AccountKey> = []

        for index in jobs.indices {
            if Task.isCancelled {
                jobs[index].state = .cancelled
                continue
            }
            let video = jobs[index].video
            if let existing = alreadyInCloud[video.id] {
                jobs[index].account = existing.accountKey
                movedEntries.append(existing)
                jobs[index].state = .moved
                continue
            }
            guard let key = allocator.allocate(sizeBytes: video.sizeBytes, preferred: preferred) else {
                jobs[index].state = .failed(connected.isEmpty ? "Connect a cloud account first." : CloudProviderError.notEnoughSpace.localizedDescription)
                continue
            }
            jobs[index].account = key
            do {
                let entry = try await move(video, at: index, to: key, workDirectory: workDirectory, context: context)
                touchedAccounts.insert(key)
                movedEntries.append(entry)
                jobs[index].state = .moved
            } catch let error as VerificationFailed {
                touchedAccounts.insert(key)
                jobs[index].state = .keptOnPhone(error.localizedDescription)
            } catch is CancellationError {
                allocator.release(sizeBytes: video.sizeBytes, from: key)
                jobs[index].state = .cancelled
            } catch {
                allocator.release(sizeBytes: video.sizeBytes, from: key)
                jobs[index].state = Task.isCancelled ? .cancelled : .failed(error.localizedDescription)
            }
            reportBackgroundProgress()
        }
        try? FileManager.default.removeItem(at: workDirectory)

        var result = Summary(
            movedCount: movedEntries.count,
            keptCount: jobs.filter(\.state.isKeptOnPhone).count,
            failedCount: jobs.filter(\.state.isFailed).count
        )

        // One confirmation for the whole batch. Deleting needs the app on screen, so wait for the user.
        if deleteAfterMove && !movedEntries.isEmpty {
            isWaitingToDelete = true
            background.update(fractionCompleted: 1, subtitle: "Open Storage Manager to finish")
            while UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .seconds(1))
            }
            do {
                try await photos.deleteVideos(withIdentifiers: movedEntries.map(\.originalAssetIdentifier))
                for entry in movedEntries { entry.deletedFromDevice = true }
                result.deletedFromPhone = true
                let localIDs = Set(jobs.filter { $0.video.isLocallyAvailable }.map(\.video.id))
                result.freedBytes = movedEntries.filter { localIDs.contains($0.originalAssetIdentifier) }.reduce(0) { $0 + $1.sizeBytes }
            } catch {
                result.deletionDeclined = true
            }
            isWaitingToDelete = false
            try? context.save()
        }

        for key in touchedAccounts {
            try? await accounts.syncManifest(for: key, context: context)
        }
        await accounts.refreshAllQuotas(connected)
        try? context.save()

        summary = result
        isRunning = false
        if showsSystemProgress { background.finish(success: result.failedCount == 0) }
    }

    // MARK: One video

    private func move(_ video: VideoAsset, at index: Int, to key: AccountKey, workDirectory: URL, context: ModelContext) async throws -> MovedVideo {
        let provider = try accounts.requireProvider(for: key)

        // 1. Export the original bytes (downloads from iCloud first if needed).
        jobs[index].state = .preparing(0)
        let videoDirectory = workDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: videoDirectory) }
        let fileURL = try await photos.exportOriginal(video, to: videoDirectory) { [weak self] fraction in
            Task { @MainActor in self?.setState(.preparing(fraction), at: index) }
        }
        try Task.checkCancellation()
        let localSize = try FileHasher.fileSize(of: fileURL)

        // Hash while uploading; both read the same file.
        let checksumKind = provider.checksumKind
        let hashTask = Task.detached(priority: .utility) {
            try FileHasher.checksum(of: fileURL, kind: checksumKind)
        }
        defer { hashTask.cancel() }

        // 2. Analyze on-device: thumbnail, scene labels, place, title.
        jobs[index].state = .analyzing
        let thumbnail = await photos.catalogThumbnailJPEG(for: video.id)
        let insight = await insights.insight(
            thumbnailJPEG: thumbnail, latitude: video.latitude, longitude: video.longitude,
            date: video.creationDate, durationSeconds: video.durationSeconds, useAI: settings.useAppleIntelligence
        )

        // 3. Upload.
        let filename = CloudPaths.filename(title: insight.title, date: video.creationDate, originalFilename: video.filename)
        let metadata = UploadMetadata(
            folderPath: CloudPaths.folderPath(for: video.creationDate),
            filename: filename,
            mimeType: CloudPaths.mimeType(forFilename: filename),
            createdAt: video.creationDate,
            description: "Moved from iPhone by Storage Manager. Original file: \(video.filename)"
        )
        jobs[index].state = .uploading(0)
        var remote = try await provider.upload(fileURL: fileURL, metadata: metadata) { [weak self] sent in
            self?.setUploaded(sent, of: localSize, at: index)
        }

        // 4. Verify size and checksum.
        jobs[index].state = .verifying
        let localChecksum = try await hashTask.value
        if remote.checksum.isEmpty {
            remote = (try? await provider.fileInfo(for: remote)) ?? remote
        }
        let checksumMatches = switch checksumKind {
        case .md5Hex: remote.checksum.lowercased() == localChecksum.lowercased()
        case .quickXorBase64: remote.checksum == localChecksum
        }
        let verified = remote.sizeBytes == localSize && !remote.checksum.isEmpty && checksumMatches

        // 5. Record it in the catalog either way: the file is in the cloud.
        let entry = MovedVideo(
            originalFilename: video.filename,
            title: insight.title,
            placeName: insight.placeName,
            keywords: insight.keywords.joined(separator: " "),
            sizeBytes: localSize,
            durationSeconds: video.durationSeconds,
            pixelWidth: video.pixelWidth,
            pixelHeight: video.pixelHeight,
            createdAt: video.creationDate,
            location: video.location,
            originalAssetIdentifier: video.id,
            provider: key.provider,
            providerUserID: key.providerUserID,
            remoteFileID: remote.id,
            remotePath: remote.path,
            checksum: remote.checksum.isEmpty ? localChecksum : remote.checksum,
            thumbnailJPEG: thumbnail
        )
        entry.isVerified = verified
        context.insert(entry)
        try context.save()

        guard verified else { throw VerificationFailed(remoteSize: remote.sizeBytes, localSize: localSize) }
        return entry
    }

    // MARK: Progress

    private func setState(_ state: JobState, at index: Int) {
        guard jobs.indices.contains(index), !jobs[index].state.isFinished else { return }
        jobs[index].state = state
    }

    private func setUploaded(_ bytes: Int64, of total: Int64, at index: Int) {
        guard jobs.indices.contains(index) else { return }
        jobs[index].uploadedBytes = bytes
        jobs[index].state = .uploading(total > 0 ? Double(bytes) / Double(total) : 1)
        isPausedForLowPower = TransferThrottle.shouldPause
        reportBackgroundProgress()
    }

    private func reportBackgroundProgress() {
        guard reportsBackgroundProgress else { return }
        let subtitle = "\(finishedCount) of \(jobs.count) · \(ByteFormatting.string(completedBytes)) of \(ByteFormatting.string(totalBytes))"
        background.update(fractionCompleted: fractionCompleted, subtitle: subtitle)
    }
}

struct VerificationFailed: LocalizedError {
    let remoteSize: Int64
    let localSize: Int64
    var errorDescription: String? {
        "The cloud copy couldn't be verified, so the original was kept on your iPhone."
    }
}
