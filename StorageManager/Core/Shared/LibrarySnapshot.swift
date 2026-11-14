import Foundation

/// A read-only copy of the catalog and storage stats, written by the app into the App Group.
/// The Files extension and the widgets read it instead of opening the CloudKit-backed SwiftData
/// store from several processes.
nonisolated struct LibrarySnapshot: Codable, Sendable, Equatable {
    static let currentVersion = 1

    var version = LibrarySnapshot.currentVersion
    /// Increases on every write; the Files extension uses it as its sync anchor.
    var generation: Int
    var generatedAt: Date
    var accounts: [Account]
    var videos: [Video]
    var phone: PhoneStats

    nonisolated struct Account: Codable, Sendable, Equatable, Identifiable {
        var provider: ProviderKind
        var providerUserID: String
        var email: String
        var totalBytes: Int64
        var usedBytes: Int64
        var isConnected: Bool

        var key: AccountKey { AccountKey(provider: provider, providerUserID: providerUserID) }
        var id: String { key.description }
        var freeBytes: Int64 { max(0, totalBytes - usedBytes) }
    }

    nonisolated struct Video: Codable, Sendable, Equatable, Identifiable {
        var catalogID: UUID
        var title: String
        var originalFilename: String
        var sizeBytes: Int64
        var durationSeconds: Double
        var createdAt: Date?
        var movedAt: Date
        var provider: ProviderKind
        var providerUserID: String
        var remoteFileID: String
        var remotePath: String
        var checksum: String
        var deletedFromDevice: Bool

        var id: UUID { catalogID }
        var accountKey: AccountKey { AccountKey(provider: provider, providerUserID: providerUserID) }
        var remoteFile: RemoteFile { RemoteFile(id: remoteFileID, path: remotePath, sizeBytes: sizeBytes, checksum: checksum) }
        /// The readable cloud file name, e.g. "2024-07-14 16.05 Beach.mov".
        var displayFilename: String {
            let last = (remotePath as NSString).lastPathComponent
            return last.isEmpty ? originalFilename : last
        }
    }

    nonisolated struct PhoneStats: Codable, Sendable, Equatable {
        var videoCount: Int
        var videoBytes: Int64
        var reclaimableBytes: Int64
        /// Videos already verified in the cloud but still on the phone.
        var pendingCleanupCount: Int
        var pendingCleanupBytes: Int64
        var lastScan: Date?
    }

    static let empty = LibrarySnapshot(
        generation: 0, generatedAt: .distantPast, accounts: [], videos: [],
        phone: PhoneStats(videoCount: 0, videoBytes: 0, reclaimableBytes: 0, pendingCleanupCount: 0, pendingCleanupBytes: 0, lastScan: nil)
    )

    var cloudFreeBytes: Int64 { accounts.filter(\.isConnected).reduce(0) { $0 + $1.freeBytes } }
    var cloudVideoBytes: Int64 { videos.reduce(0) { $0 + $1.sizeBytes } }
    var freedBytes: Int64 { videos.filter(\.deletedFromDevice).reduce(0) { $0 + $1.sizeBytes } }

    static func load(from url: URL = SharedContainer.snapshotURL) -> LibrarySnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? CatalogManifest.decoder.decode(LibrarySnapshot.self, from: data)
    }

    func save(to url: URL = SharedContainer.snapshotURL) throws {
        try CatalogManifest.encoder.encode(self).write(to: url, options: [.atomic])
    }
}
