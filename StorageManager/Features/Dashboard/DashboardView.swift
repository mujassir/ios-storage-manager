import SwiftUI
import SwiftData

struct DashboardView: View {
    @Binding var selectedTab: AppTab
    let iCloudStatus: ICloudStatus

    @Environment(LibraryScanner.self) private var scanner
    @Environment(AccountManager.self) private var accounts
    @Environment(TransferEngine.self) private var transfers
    @Environment(AutoMoveService.self) private var autoMove
    @Environment(ProStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query private var linkedAccounts: [LinkedAccount]
    @Query private var movedVideos: [MovedVideo]
    @AppStorage("videos.filter") private var videoFilter: VideoFilter = .all
    @State private var isFreeing = false
    @State private var freedMessage: String?
    @State private var showProgress = false

    /// Verified in the cloud but still on this phone (auto-move, or deletion wasn't confirmed).
    private var pendingCleanup: [MovedVideo] {
        let onPhone = Set(scanner.videos.map(\.id))
        return movedVideos.filter { $0.isPendingCleanup && onPhone.contains($0.originalAssetIdentifier) }
    }

    private var autoMovePlan: [AutoMoveRule.Destination: [VideoAsset]] {
        store.isPro && autoMove.hasEnabledRules && !transfers.isRunning ? autoMove.plan(for: scanner.videos) : [:]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let message = iCloudStatus.message {
                        ErrorBanner(message: message, systemImage: "icloud.slash")
                    }
                    if let error = scanner.errorMessage {
                        ErrorBanner(message: error)
                    }
                    if transfers.isRunning {
                        activeTransferCard
                    }
                    if !pendingCleanup.isEmpty || freedMessage != nil {
                        cleanupCard
                    }
                    if !autoMovePlan.isEmpty {
                        autoMoveCard
                    }
                    phoneCard
                    cloudCard
                    suggestionsCard
                    biggestVideosCard
                }
                .padding()
            }
            .navigationTitle("Storage")
            .refreshable { await refresh() }
            .task { if scanner.lastScan == nil { await refresh() } }
            .sheet(isPresented: $showProgress) { TransferProgressView() }
        }
    }

    private func refresh() async {
        await scanner.scan()
        await accounts.refreshAllQuotas(linkedAccounts)
    }

    // MARK: Cards

    private var cleanupCard: some View {
        let bytes = pendingCleanup.reduce(0) { $0 + $1.sizeBytes }
        return Card {
            Label("Ready to free", systemImage: "sparkles").font(.headline).foregroundStyle(.green)
            if let freedMessage, pendingCleanup.isEmpty {
                Text(freedMessage)
                Text("To free the space now, empty Photos › Recently Deleted.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("\(pendingCleanup.count) video\(pendingCleanup.count == 1 ? " is" : "s are") safely in your cloud and verified, but still on this iPhone.")
                    .foregroundStyle(.secondary)
                Button {
                    Task { await freeUp() }
                } label: {
                    HStack {
                        Text("Free \(ByteFormatting.string(bytes))")
                        if isFreeing { ProgressView() }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(isFreeing)
            }
        }
    }

    private var autoMoveCard: some View {
        let videos = autoMovePlan.values.flatMap { $0 }
        return Card {
            Label("Auto-move", systemImage: "wand.and.stars").font(.headline)
            Text("Your rules match \(videos.count) video\(videos.count == 1 ? "" : "s") (\(ByteFormatting.string(videos.reduce(0) { $0 + $1.sizeBytes }))). They'll move overnight while charging, or you can move them now.")
                .foregroundStyle(.secondary)
            Button("Move Now") {
                for (destination, batch) in autoMovePlan.sorted(by: { $0.value.count > $1.value.count }).prefix(1) {
                    transfers.start(batch, destination: AutoMoveService.engineDestination(destination), deleteAfterMove: true, context: context)
                }
                showProgress = true
            }
            .buttonStyle(.glass)
        }
    }

    private func freeUp() async {
        isFreeing = true
        defer { isFreeing = false }
        let bytes = pendingCleanup.reduce(0) { $0 + $1.sizeBytes }
        do {
            _ = try await transfers.freeUpVerifiedOriginals(context: context, onDevice: scanner.videos)
            freedMessage = "Deleted \(ByteFormatting.string(bytes)) of videos that are safe in your cloud."
            await scanner.scan()
        } catch {
            // The user declined the iOS confirmation; nothing changed.
        }
    }

    private var phoneCard: some View {
        Card {
            Label("iPhone", systemImage: "iphone").font(.headline)
            UsageBar(used: scanner.deviceStorage.usedBytes, total: scanner.deviceStorage.totalBytes)
            HStack {
                Text("\(ByteFormatting.string(scanner.deviceStorage.availableBytes)) free")
                Spacer()
                Text("of \(ByteFormatting.string(scanner.deviceStorage.totalBytes))")
            }
            .font(.subheadline).foregroundStyle(.secondary)
            Divider()
            if scanner.isScanning && scanner.videos.isEmpty {
                ProgressView("Scanning videos…").frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(ByteFormatting.string(scanner.totalVideoBytes)).font(.title.bold())
                        Text("in \(scanner.videos.count) videos").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(ByteFormatting.string(scanner.reclaimableBytes)).font(.title3.bold()).foregroundStyle(.green)
                        Text("can be freed").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var cloudCard: some View {
        let connected = linkedAccounts.filter { accounts.isConnected($0) }
        let free = connected.compactMap { accounts.quota(for: $0)?.freeBytes }.reduce(0, +)
        let movedBytes = movedVideos.reduce(0) { $0 + $1.sizeBytes }
        return Card {
            Label("Your clouds", systemImage: "cloud").font(.headline)
            if connected.isEmpty {
                Text("Connect a free cloud account to start moving videos.")
                    .foregroundStyle(.secondary)
                Button("Connect a Cloud") { selectedTab = .clouds }
                    .buttonStyle(.glassProminent)
            } else {
                HStack {
                    VStack(alignment: .leading) {
                        Text(ByteFormatting.string(free)).font(.title2.bold())
                        Text("free across \(connected.count) account\(connected.count == 1 ? "" : "s")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(movedVideos.count)").font(.title2.bold())
                        Text("videos · \(ByteFormatting.string(movedBytes))").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if linkedAccounts.count > connected.count {
                    Button("Reconnect \(linkedAccounts.count - connected.count) account(s)") { selectedTab = .clouds }
                        .font(.subheadline)
                }
            }
        }
    }

    private var suggestionsCard: some View {
        Card {
            Label("Suggestions", systemImage: "sparkles").font(.headline)
            ForEach([VideoFilter.large, .old, .screenRecordings]) { filter in
                let count = scanner.count(matching: filter)
                Button {
                    videoFilter = filter
                    selectedTab = .videos
                } label: {
                    HStack {
                        Text(filter.title)
                        Spacer()
                        Text("\(count) · \(ByteFormatting.string(scanner.bytes(matching: filter)))")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .disabled(count == 0)
            }
        }
    }

    private var biggestVideosCard: some View {
        Card {
            Label("Biggest videos", systemImage: "arrow.up.right.video").font(.headline)
            if scanner.videos.isEmpty {
                Text(scanner.isScanning ? "Scanning…" : "No videos found.").foregroundStyle(.secondary)
            }
            ForEach(scanner.videos.prefix(5)) { video in
                HStack(spacing: 12) {
                    AssetThumbnail(identifier: video.id, side: 48)
                    VStack(alignment: .leading) {
                        Text(video.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? video.filename)
                        Text(DurationFormatting.string(video.durationSeconds)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(ByteFormatting.string(video.sizeBytes)).font(.subheadline.monospacedDigit())
                }
            }
            if scanner.videos.count > 5 {
                Button("See all videos") {
                    videoFilter = .all
                    selectedTab = .videos
                }
            }
        }
    }

    private var activeTransferCard: some View {
        Card {
            Label("Moving videos", systemImage: "arrow.up.circle").font(.headline)
            ProgressView(value: transfers.fractionCompleted)
            Text("\(transfers.finishedCount) of \(transfers.jobs.count) · \(ByteFormatting.string(transfers.completedBytes)) of \(ByteFormatting.string(transfers.totalBytes))")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Show Progress") { selectedTab = .videos }
        }
    }
}

/// Rounded container used by dashboard sections.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 20))
    }
}
