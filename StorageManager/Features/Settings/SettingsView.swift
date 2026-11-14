import SwiftUI
import SwiftData

struct SettingsView: View {
    let iCloudStatus: ICloudStatus

    @Environment(AppSettings.self) private var settings
    @Environment(VideoInsightService.self) private var insights
    @Environment(AccountManager.self) private var accounts
    @Environment(\.modelContext) private var context
    @Query private var linkedAccounts: [LinkedAccount]

    @State private var rebuildMessage: String?
    @State private var isRebuilding = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Toggle("Upload on Wi-Fi only", isOn: $settings.wifiOnly)
                    Toggle("Pause in Low Power Mode", isOn: $settings.pauseOnLowPower)
                    Toggle("Delete from iPhone after upload", isOn: $settings.deleteAfterMove)
                } header: {
                    Text("Moving Videos")
                } footer: {
                    Text("A video is only deleted after the cloud copy is verified.")
                }

                Section {
                    Toggle("Smart titles and search", isOn: $settings.useAppleIntelligence)
                    LabeledContent("Apple Intelligence", value: insights.availabilityDescription)
                } header: {
                    Text("On-Device Intelligence")
                } footer: {
                    Text("Titles and search run entirely on your iPhone with Apple Intelligence. Nothing is sent to a server.")
                }

                Section {
                    LabeledContent("iCloud sync", value: iCloudStatus == .available ? "On" : "Off")
                    Button {
                        Task { await rebuild() }
                    } label: {
                        HStack {
                            Text("Rebuild Library from Clouds")
                            if isRebuilding { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isRebuilding)
                    if let rebuildMessage {
                        Text(rebuildMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Library")
                } footer: {
                    Text("Your library list syncs through your private iCloud. A copy is also kept in each cloud account, so it can be rebuilt if needed.")
                }

                Section {
                    NavigationLink("Privacy") { PrivacyView() }
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func rebuild() async {
        isRebuilding = true
        defer { isRebuilding = false }
        var added = 0
        var failures = 0
        for account in linkedAccounts where accounts.isConnected(account) {
            do {
                added += try await accounts.importManifest(for: account, context: context)
            } catch {
                failures += 1
            }
        }
        rebuildMessage = failures > 0
            ? "Added \(added) videos. \(failures) account(s) couldn't be read."
            : "Library is up to date. Added \(added) videos."
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("Your videos go straight to your cloud").font(.headline)
                    Text("Storage Manager uploads videos directly from your iPhone to the cloud accounts you connect. There is no Storage Manager server, and the developer never receives your videos, photos, or account details.")
                    Text("Sign-in stays on your iPhone").font(.headline)
                    Text("Sign-in tokens are stored in this iPhone's Keychain, marked “this device only”. They are not synced to iCloud, not included in backups, and never leave the device. Disconnecting an account deletes them.")
                    Text("Your library list is in your iCloud").font(.headline)
                    Text("The list of moved videos (titles, dates, sizes, small thumbnails) is kept in your private iCloud database, which only you can access, plus a copy in each cloud account.")
                    Text("Intelligence runs on-device").font(.headline)
                    Text("Scene labels, titles and search use Apple's on-device Vision and Apple Intelligence models. Place names are looked up with Apple Maps.")
                    Text("Limited access").font(.headline)
                    Text("On OneDrive the app can only use its own app folder. On Google Drive it can only see files it created.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle("Privacy")
    }
}
