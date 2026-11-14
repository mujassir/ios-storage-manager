import Foundation

/// Creates the app's long-lived services once and wires them together.
final class AppEnvironment {
    let settings = AppSettings()
    let photos = PhotoLibraryService()
    let accounts = AccountManager()
    let insights = VideoInsightService()
    let search = LibrarySearchInterpreter()
    let background = ContinuedProcessingCoordinator()
    let scanner: LibraryScanner
    let transfers: TransferEngine
    let restores: RestoreService

    init() {
        scanner = LibraryScanner(photos: photos)
        transfers = TransferEngine(photos: photos, accounts: accounts, insights: insights, settings: settings, background: background)
        restores = RestoreService(photos: photos, accounts: accounts)
    }
}
