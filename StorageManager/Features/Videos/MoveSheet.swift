import SwiftUI
import SwiftData

/// Confirms a move: where to, whether to delete from the phone, and what to expect.
struct MoveSheet: View {
    let videos: [VideoAsset]
    @Binding var selectedTab: AppTab
    let onStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AccountManager.self) private var accounts
    @Environment(TransferEngine.self) private var transfers
    @Environment(AppSettings.self) private var settings
    @Environment(ProStore.self) private var store
    @Query(sort: \LinkedAccount.linkedAt) private var linkedAccounts: [LinkedAccount]

    @State private var destination: TransferEngine.Destination = .automatic
    @State private var deleteAfterMove = true
    @State private var showPaywall = false

    private var connected: [LinkedAccount] { linkedAccounts.filter { accounts.isConnected($0) } }
    private var totalBytes: Int64 { videos.reduce(0) { $0 + $1.sizeBytes } }
    private var iCloudOnlyCount: Int { videos.filter { !$0.isLocallyAvailable }.count }
    private var largestVideo: Int64 { videos.map(\.sizeBytes).max() ?? 0 }

    private var freeBytesForDestination: Int64 {
        switch destination {
        case .automatic:
            connected.compactMap { accounts.quota(for: $0)?.freeBytes }.reduce(0, +)
        case .account(let key):
            connected.first { $0.accountKey == key }.flatMap { accounts.quota(for: $0)?.freeBytes } ?? 0
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Videos", value: "\(videos.count)")
                    LabeledContent("Total size", value: ByteFormatting.string(totalBytes))
                }

                if !store.canMove(count: videos.count) {
                    Section {
                        Label("The free version moves up to \(ProStore.freeBatchLimit) videos at a time. Move the first \(ProStore.freeBatchLimit) now, or get Pro for unlimited moves.", systemImage: "lock")
                            .font(.footnote)
                        Button("Get Pro") { showPaywall = true }
                    }
                }

                if connected.isEmpty {
                    Section {
                        Text("Connect a cloud account first.")
                        Button("Go to Clouds") {
                            dismiss()
                            selectedTab = .clouds
                        }
                    }
                } else {
                    Section {
                        Picker("Move to", selection: $destination) {
                            Text("Automatic (most free space)").tag(TransferEngine.Destination.automatic)
                            ForEach(connected) { account in
                                Text("\(account.provider.displayName) · \(account.email)")
                                    .tag(TransferEngine.Destination.account(account.accountKey))
                            }
                        }
                        LabeledContent("Free space", value: ByteFormatting.string(freeBytesForDestination))
                        if freeBytesForDestination < totalBytes {
                            Label("Not all videos may fit. Ones that don't will stay on your iPhone.", systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    } footer: {
                        Text("Videos are uploaded in original quality to “Storage Manager/Videos” in your cloud.")
                    }

                    Section {
                        Toggle("Delete from iPhone after upload", isOn: $deleteAfterMove)
                    } footer: {
                        Text(deleteAfterMove
                             ? "Each video is checked against the cloud copy before it's deleted. iOS will ask you to confirm once, and keeps deleted videos in Recently Deleted for 30 days."
                             : "Videos will be copied to the cloud and kept on your iPhone.")
                    }

                    if iCloudOnlyCount > 0 {
                        Section {
                            Label("\(iCloudOnlyCount) of these videos are stored in iCloud Photos, not on this iPhone. They'll be downloaded first, and moving them frees little space here.", systemImage: "icloud")
                                .font(.footnote)
                        }
                    }

                    if settings.wifiOnly {
                        Section {
                            Label("Uploads use Wi-Fi only. You can change this in Settings.", systemImage: "wifi")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Move Videos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move", role: .confirm) {
                        let batch = store.canMove(count: videos.count) ? videos : Array(videos.prefix(ProStore.freeBatchLimit))
                        transfers.start(batch, destination: destination, deleteAfterMove: deleteAfterMove, context: context)
                        dismiss()
                        onStart()
                    }
                    .disabled(connected.isEmpty || transfers.isRunning)
                }
            }
            .onAppear { deleteAfterMove = settings.deleteAfterMove }
            .sheet(isPresented: $showPaywall) {
                ProPaywallView(reason: "Move all \(videos.count) videos in one go.")
            }
        }
    }
}
