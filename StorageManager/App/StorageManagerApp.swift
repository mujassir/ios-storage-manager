import SwiftUI
import SwiftData
import AVFoundation

@main
struct StorageManagerApp: App {
    private let environment: AppEnvironment
    private let container: ModelContainer

    init() {
        environment = AppEnvironment()
        container = Self.makeModelContainer()
        // Lets cloud videos keep playing in Picture in Picture.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment.settings)
                .environment(environment.accounts)
                .environment(environment.scanner)
                .environment(environment.transfers)
                .environment(environment.restores)
                .environment(environment.insights)
                .environment(environment.search)
                .environment(environment.photos)
        }
        .modelContainer(container)
    }

    /// The catalog lives in the user's private CloudKit database, so it follows them to a new iPhone.
    /// If CloudKit can't be set up (e.g. a build without the iCloud capability), fall back to a local store.
    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([LinkedAccount.self, MovedVideo.self])
        let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .private(AppConfig.cloudKitContainer))
        if let container = try? ModelContainer(for: schema, configurations: cloud) {
            return container
        }
        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            fatalError("Couldn't open the library database: \(error)")
        }
    }
}
