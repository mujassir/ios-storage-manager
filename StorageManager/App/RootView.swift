import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case storage, videos, library, clouds, settings
}

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AccountManager.self) private var accounts
    @Environment(\.modelContext) private var context
    @Query(sort: \LinkedAccount.linkedAt) private var linkedAccounts: [LinkedAccount]

    @State private var selectedTab: AppTab = .storage
    @State private var welcomeBackDismissed = false
    @State private var iCloudStatus: ICloudStatus = .checking

    private var accountsNeedingReconnect: [LinkedAccount] {
        linkedAccounts.filter { !accounts.isConnected($0) }
    }

    var body: some View {
        if settings.hasCompletedOnboarding {
            mainTabs
        } else {
            OnboardingView()
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Storage", systemImage: "internaldrive", value: AppTab.storage) {
                DashboardView(selectedTab: $selectedTab, iCloudStatus: iCloudStatus)
            }
            Tab("Videos", systemImage: "video", value: AppTab.videos) {
                VideoListView(selectedTab: $selectedTab)
            }
            Tab("Library", systemImage: "play.rectangle.on.rectangle", value: AppTab.library) {
                LibraryView(selectedTab: $selectedTab)
            }
            Tab("Clouds", systemImage: "cloud", value: AppTab.clouds) {
                AccountsView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView(iCloudStatus: iCloudStatus)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: welcomeBackBinding) {
            WelcomeBackView(accounts: accountsNeedingReconnect) {
                welcomeBackDismissed = true
            }
        }
        .task {
            accounts.removeDuplicateAccounts(context: context)
            iCloudStatus = await ICloudStatus.check()
        }
    }

    /// On a new iPhone, accounts arrive from iCloud without tokens: offer to reconnect them.
    private var welcomeBackBinding: Binding<Bool> {
        Binding(
            get: { !welcomeBackDismissed && !accountsNeedingReconnect.isEmpty },
            set: { if !$0 { welcomeBackDismissed = true } }
        )
    }
}
