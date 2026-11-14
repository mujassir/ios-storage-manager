import Foundation

/// Values injected at build time from `Config/App.xcconfig` + `Secrets.xcconfig` via Info.plist.
nonisolated enum AppConfig {
    /// The main app's bundle ID, also inside extensions (whose own bundle IDs have a suffix).
    static var bundleID: String {
        let configured = string("SMAppBundleID")
        return configured.isEmpty ? (Bundle.main.bundleIdentifier ?? "com.yourco.storagemanager") : configured
    }
    /// Shared container for the app, the Files extension and the widgets.
    static var appGroupID: String {
        let value = string("SMAppGroupID")
        return value.isEmpty ? "group.\(bundleID)" : value
    }
    /// Keychain group shared with the Files extension so it can download videos on demand.
    static var keychainAccessGroup: String { string("SMKeychainAccessGroup") }
    static let urlScheme = "storagemanager"
    static var googleClientID: String { string("SMGoogleClientID") }
    static var microsoftClientID: String { string("SMMicrosoftClientID") }
    static var cloudKitContainer: String {
        let value = string("SMCloudKitContainer")
        return value.isEmpty ? "iCloud.\(bundleID)" : value
    }
    static var moveTaskIdentifier: String { "\(bundleID).move" }
    static var autoMoveTaskIdentifier: String { "\(bundleID).automove" }
    static let fileProviderDomainID = "library"

    /// Name of the app's root folder inside each cloud account.
    static let cloudRootFolderName = "Storage Manager"
    static let manifestFilename = "index.json"

    private static func string(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
