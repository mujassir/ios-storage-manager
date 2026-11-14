import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case storage, videos, library, clouds, settings
}

/// Opened from widgets, notifications and the Files app: `storagemanager://videos?filter=large`.
enum DeepLink: Equatable {
    case storage, cleanup, library, clouds, settings
    case videos(VideoFilter?)

    init?(url: URL) {
        guard url.scheme == AppConfig.urlScheme else { return nil }
        let filter = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "filter" }?.value.flatMap(VideoFilter.init(rawValue:))
        switch url.host() {
        case "storage", nil: self = .storage
        case "cleanup": self = .cleanup
        case "library": self = .library
        case "clouds": self = .clouds
        case "settings": self = .settings
        case "videos": self = .videos(filter)
        default: return nil
        }
    }

    var tab: AppTab {
        switch self {
        case .storage, .cleanup: .storage
        case .library: .library
        case .clouds: .clouds
        case .settings: .settings
        case .videos: .videos
        }
    }
}

struct RootView: View {
    let refreshExtensions: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(LibraryScanner.self) private var scanner
    @Environment(TransferEngine.self) private var transfers
    @Environment(AccountManager.self) private var accounts
    @Environment(\.modelContext) private var context
    @Query(sort: \LinkedAccount.linkedAt) private var linkedAccounts: [LinkedAccount]
    @Query private var movedVideos: [MovedVideo]
    @AppStorage("videos.filter") private var videoFilter: VideoFilter = .all

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
        // Tab bar on iPhone, sidebar on iPad and Mac.
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .onOpenURL { url in
            guard let link = DeepLink(url: url) else { return }
            if case .videos(let filter?) = link { videoFilter = filter }
            selectedTab = link.tab
        }
        // Keep the Files app and widgets in step with the library.
        .onChange(of: movedVideos.count) { refreshExtensions() }
        .onChange(of: linkedAccounts.count) { refreshExtensions() }
        .onChange(of: scanner.lastScan) { refreshExtensions() }
        .onChange(of: transfers.isRunning) { refreshExtensions() }
        .onChange(of: accounts.connectionRevision) { refreshExtensions() }
        .sheet(isPresented: welcomeBackBinding) {
            WelcomeBackView(accounts: accountsNeedingReconnect) {
                welcomeBackDismissed = true
            }
        }
        .task {
            accounts.removeDuplicateAccounts(context: context)
            refreshExtensions()
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
