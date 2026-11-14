import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(AccountManager.self) private var accounts
    @Query(sort: \LinkedAccount.linkedAt) private var linkedAccounts: [LinkedAccount]
    @Query private var movedVideos: [MovedVideo]

    @State private var busyProvider: ProviderKind?
    @State private var errorMessage: String?
    @State private var accountToDisconnect: LinkedAccount?

    private var totalFree: Int64 {
        linkedAccounts.filter { accounts.isConnected($0) }.compactMap { accounts.quota(for: $0)?.freeBytes }.reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            List {
                if !linkedAccounts.isEmpty {
                    Section {
                        ForEach(linkedAccounts) { account in
                            AccountRow(
                                account: account,
                                isConnected: accounts.isConnected(account),
                                quota: accounts.quota(for: account),
                                videoCount: movedVideos.filter { $0.accountKey == account.accountKey }.count,
                                isBusy: busyProvider == account.provider,
                                reconnect: { connect(account.provider, reconnecting: account) }
                            )
                            .swipeActions {
                                Button("Disconnect", role: .destructive) { accountToDisconnect = account }
                            }
                        }
                    } header: {
                        Text("Your Clouds")
                    } footer: {
                        Text("\(ByteFormatting.string(totalFree)) free in total. Sign-in tokens stay on this iPhone only; they are never synced or sent to us.")
                    }
                }

                Section {
                    ForEach(ProviderKind.allCases) { kind in
                        Button {
                            connect(kind, reconnecting: nil)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: kind.symbolName)
                                    .font(.title2)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Connect \(kind.displayName)").font(.body.weight(.medium))
                                    Text(kind.freeTierDescription).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if busyProvider == kind { ProgressView() }
                            }
                        }
                        .disabled(busyProvider != nil)
                    }
                } header: {
                    Text("Add a Cloud")
                } footer: {
                    Text("Storage Manager only gets access to its own folder (OneDrive) or files it creates (Google Drive). It can't see your other files.")
                }
            }
            .navigationTitle("Clouds")
            .refreshable { await accounts.refreshAllQuotas(linkedAccounts) }
            .alert("Couldn't Connect", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog(
                "Disconnect \(accountToDisconnect?.email ?? "")?",
                isPresented: Binding(get: { accountToDisconnect != nil }, set: { if !$0 { accountToDisconnect = nil } }),
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    if let account = accountToDisconnect { try? accounts.disconnect(account, context: context) }
                    accountToDisconnect = nil
                }
            } message: {
                Text("Your videos stay in this cloud account and in your library list, but can't be played or restored until you connect it again.")
            }
        }
    }

    private func connect(_ kind: ProviderKind, reconnecting existing: LinkedAccount?) {
        busyProvider = kind
        Task {
            defer { busyProvider = nil }
            do {
                try await accounts.connect(kind, reconnecting: existing, presenter: webAuthenticationSession.presenter, context: context)
            } catch let error where !error.isUserCancelledSignIn {
                errorMessage = error.localizedDescription
            } catch {}
        }
    }
}

struct AccountRow: View {
    let account: LinkedAccount
    let isConnected: Bool
    let quota: StorageQuota?
    let videoCount: Int
    let isBusy: Bool
    let reconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: account.provider.symbolName).font(.title2).frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.provider.displayName).font(.headline)
                    Text(account.email).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if isBusy {
                    ProgressView()
                } else if !isConnected {
                    Button("Reconnect", action: reconnect).buttonStyle(.glassProminent)
                }
            }
            if let quota, quota.totalBytes > 0 {
                UsageBar(used: quota.usedBytes, total: quota.totalBytes)
                HStack {
                    Text("\(ByteFormatting.string(quota.freeBytes)) free of \(ByteFormatting.string(quota.totalBytes))")
                    Spacer()
                    Text("\(videoCount) videos")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
