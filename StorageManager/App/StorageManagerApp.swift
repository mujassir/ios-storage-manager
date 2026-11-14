import SwiftUI
import SwiftData
import AVFoundation

@main
struct StorageManagerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let environment: AppEnvironment

    init() {
        environment = AppEnvironment()
        // Lets cloud videos keep playing in Picture in Picture.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView(refreshExtensions: environment.refreshExtensions)
                .environment(environment.settings)
                .environment(environment.accounts)
                .environment(environment.scanner)
                .environment(environment.transfers)
                .environment(environment.restores)
                .environment(environment.insights)
                .environment(environment.search)
                .environment(environment.photos)
                .environment(environment.store)
                .environment(environment.autoMove)
        }
        .modelContainer(environment.container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                environment.refreshExtensions()
                environment.autoMove.schedule()
            case .active:
                Task { await environment.store.refreshEntitlements() }
            default:
                break
            }
        }
    }
}
