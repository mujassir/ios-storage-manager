import Foundation

/// Values injected at build time from `Config/App.xcconfig` + `Secrets.xcconfig` via Info.plist.
nonisolated enum AppConfig {
    static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.yourco.storagemanager" }
    static var googleClientID: String { string("SMGoogleClientID") }
    static var microsoftClientID: String { string("SMMicrosoftClientID") }
    static var cloudKitContainer: String {
        let value = string("SMCloudKitContainer")
        return value.isEmpty ? "iCloud.\(bundleID)" : value
    }
    static var moveTaskIdentifier: String { "\(bundleID).move" }

    /// Name of the app's root folder inside each cloud account.
    static let cloudRootFolderName = "Storage Manager"
    static let manifestFilename = "index.json"

    private static func string(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
