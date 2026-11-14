import Foundation

/// The App Group shared by the app, the Files (File Provider) extension and the widgets.
nonisolated enum SharedContainer {
    static var defaults: UserDefaults {
        UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    }

    /// Root of the shared container, or a private fallback if the App Group isn't configured.
    static var directory: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID) {
            return url
        }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Shared")
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    static var snapshotURL: URL { directory.appending(path: "library-snapshot.json") }

    static var thumbnailsDirectory: URL {
        let url = directory.appending(path: "Thumbnails", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func thumbnailURL(for catalogID: UUID) -> URL {
        thumbnailsDirectory.appending(path: "\(catalogID.uuidString).jpg")
    }
}
