import Foundation
import SwiftData

/// Creates the app's long-lived services once and wires them together.
final class AppEnvironment {
    let container: ModelContainer
    let settings = AppSettings()
    let photos = PhotoLibraryService()
    let accounts = AccountManager()
    let insights = VideoInsightService()
    let search = LibrarySearchInterpreter()
    let background = ContinuedProcessingCoordinator()
    let store = ProStore()
    let bridge = ExtensionBridge()
    let scanner: LibraryScanner
    let transfers: TransferEngine
    let restores: RestoreService
    let autoMove: AutoMoveService

    init() {
        container = Self.makeModelContainer()
        scanner = LibraryScanner(photos: photos)
        transfers = TransferEngine(photos: photos, accounts: accounts, insights: insights, settings: settings, background: background)
        restores = RestoreService(photos: photos, accounts: accounts)
        autoMove = AutoMoveService(photos: photos, transfers: transfers, store: store, container: container)
    }

    /// Writes the shared snapshot for the Files extension and widgets.
    func refreshExtensions() {
        bridge.refresh(context: container.mainContext, scanner: scanner, accounts: accounts)
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
