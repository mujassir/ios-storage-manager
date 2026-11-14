import SwiftUI
import SwiftData

/// Shown on a new iPhone: the library and account list arrived from iCloud, but sign-in tokens never leave
/// a device, so each account needs one quick reconnect.
struct WelcomeBackView: View {
    let accounts: [LinkedAccount]
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(AccountManager.self) private var manager
    @Query private var movedVideos: [MovedVideo]

    @State private var busyAccount: PersistentIdentifier?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "hand.wave.fill").font(.largeTitle).foregroundStyle(.tint)
                        Text("Welcome back!").font(.title.bold())
                        Text("\(movedVideos.count) videos (\(ByteFormatting.string(movedVideos.reduce(0) { $0 + $1.sizeBytes }))) are safe in your clouds. Reconnect each account to watch and restore them on this iPhone.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                Section("Accounts") {
                    ForEach(accounts) { account in
                        HStack {
                            Image(systemName: account.provider.symbolName).frame(width: 30)
                            VStack(alignment: .leading) {
                                Text(account.provider.displayName).font(.headline)
                                Text(account.email).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if busyAccount == account.persistentModelID {
                                ProgressView()
                            } else if manager.isConnected(account) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Button("Reconnect") { reconnect(account) }
                                    .buttonStyle(.glassProminent)
                                    .disabled(busyAccount != nil)
                            }
                        }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(accounts.allSatisfy(manager.isConnected) ? "Done" : "Later") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(busyAccount != nil)
    }

    private func reconnect(_ account: LinkedAccount) {
        busyAccount = account.persistentModelID
        errorMessage = nil
        Task {
            defer { busyAccount = nil }
            do {
                try await manager.connect(account.provider, reconnecting: account, presenter: webAuthenticationSession.presenter, context: context)
            } catch let error where !error.isUserCancelledSignIn {
                errorMessage = error.localizedDescription
            } catch {}
        }
    }
}
