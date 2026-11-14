import SwiftUI
import SwiftData

struct DashboardView: View {
    @Binding var selectedTab: AppTab
    let iCloudStatus: ICloudStatus

    @Environment(LibraryScanner.self) private var scanner
    @Environment(AccountManager.self) private var accounts
    @Environment(TransferEngine.self) private var transfers
    @Query private var linkedAccounts: [LinkedAccount]
    @Query private var movedVideos: [MovedVideo]
    @AppStorage("videos.filter") private var videoFilter: VideoFilter = .all

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
        }
    }

    private func refresh() async {
        await scanner.scan()
        await accounts.refreshAllQuotas(linkedAccounts)
    }

    // MARK: Cards

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
