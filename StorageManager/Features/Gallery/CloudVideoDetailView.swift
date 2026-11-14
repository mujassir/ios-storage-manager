import SwiftUI
import SwiftData
import AVKit

struct CloudVideoDetailView: View {
    let video: MovedVideo
    @Binding var selectedTab: AppTab

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AccountManager.self) private var accounts
    @Environment(RestoreService.self) private var restores
    @Query private var linkedAccounts: [LinkedAccount]

    @State private var media: PlayableMedia?
    @State private var player: AVPlayer?
    @State private var loadError: String?
    @State private var showRestoreOptions = false

    private var account: LinkedAccount? {
        linkedAccounts.first { $0.accountKey == video.accountKey }
    }
    private var isConnected: Bool { account.map(accounts.isConnected) ?? false }

    var body: some View {
        List {
            Section {
                playerArea
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.displayTitle).font(.title3.bold())
                    if let date = video.createdAt {
                        Text(date.formatted(date: .complete, time: .shortened)).foregroundStyle(.secondary)
                    }
                }
                if !video.placeName.isEmpty { LabeledContent("Place", value: video.placeName) }
                LabeledContent("Length", value: DurationFormatting.string(video.durationSeconds))
                LabeledContent("Size", value: ByteFormatting.string(video.sizeBytes))
                if video.pixelWidth > 0 { LabeledContent("Resolution", value: "\(video.pixelWidth) × \(video.pixelHeight)") }
            }

            Section("Stored in") {
                LabeledContent(video.provider.displayName, value: account?.email ?? "Disconnected account")
                Text(video.remotePath).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
            }

            Section {
                restoreButton
            } footer: {
                Text("Restoring saves the original file back to Photos at its original date and place.")
            }
        }
        .navigationTitle(video.createdAt?.formatted(date: .abbreviated, time: .omitted) ?? "Video")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: isConnected) { await loadMedia() }
        .onDisappear { player?.pause() }
        .confirmationDialog("Restore to Photos", isPresented: $showRestoreOptions, titleVisibility: .visible) {
            Button("Restore and Keep Cloud Copy") { restore(deleteCloudCopy: false) }
            Button("Restore and Remove from Cloud", role: .destructive) { restore(deleteCloudCopy: true) }
        }
    }

    private var aspectRatio: CGFloat {
        video.pixelWidth > 0 && video.pixelHeight > 0 ? CGFloat(video.pixelWidth) / CGFloat(video.pixelHeight) : 16 / 9
    }

    @ViewBuilder
    private var playerArea: some View {
        if let player {
            PlayerView(player: player)
        } else {
            ZStack {
                CatalogThumbnail(data: video.thumbnailJPEG)
                Rectangle().fill(.black.opacity(0.35))
                VStack(spacing: 10) {
                    if !isConnected {
                        Text("Reconnect \(video.provider.displayName) to play").foregroundStyle(.white)
                        Button("Go to Clouds") { selectedTab = .clouds }
                            .buttonStyle(.glass)
                    } else if let loadError {
                        Text(loadError).foregroundStyle(.white).multilineTextAlignment(.center).padding()
                        Button("Try Again") { Task { await loadMedia() } }.buttonStyle(.glass)
                    } else {
                        ProgressView().tint(.white)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var restoreButton: some View {
        switch restores.states[video.catalogID] {
        case .downloading:
            Label("Downloading…", systemImage: "arrow.down.circle")
        case .saving:
            Label("Saving to Photos…", systemImage: "photo.badge.arrow.down")
        case .restored:
            Label("Restored to Photos", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            VStack(alignment: .leading) {
                Text(message).font(.footnote).foregroundStyle(.red)
                Button("Try Again") { showRestoreOptions = true }
            }
        case nil:
            Button {
                showRestoreOptions = true
            } label: {
                Label("Restore to Photos", systemImage: "square.and.arrow.down")
            }
            .disabled(!isConnected)
        }
    }

    private func loadMedia() async {
        guard isConnected, player == nil, let provider = accounts.provider(for: video.accountKey) else { return }
        loadError = nil
        do {
            let media = try await provider.playableMedia(for: video.remoteFile, filename: video.remotePath)
            self.media = media
            player = AVPlayer(playerItem: AVPlayerItem(asset: media.asset))
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func restore(deleteCloudCopy: Bool) {
        let target = video
        // Removing the cloud copy deletes this catalog entry, so leave the screen first.
        if deleteCloudCopy {
            player?.pause()
            dismiss()
        }
        Task { await restores.restore([target], deleteCloudCopy: deleteCloudCopy, context: context) }
    }
}

/// AVPlayerViewController for full-screen, AirPlay and Picture in Picture support.
struct PlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}
