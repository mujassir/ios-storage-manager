import Foundation

/// A file stored in a cloud account.
nonisolated struct RemoteFile: Codable, Hashable, Sendable {
    var id: String
    var path: String
    var sizeBytes: Int64
    /// Provider-native checksum (see `ChecksumKind`). Empty if the provider did not report one.
    var checksum: String
}

nonisolated struct StorageQuota: Sendable, Equatable {
    var totalBytes: Int64
    var usedBytes: Int64
    var freeBytes: Int64 { max(0, totalBytes - usedBytes) }
}

/// Who the user signed in as, read from the provider after OAuth.
nonisolated struct AccountIdentity: Sendable, Equatable {
    var providerUserID: String
    var email: String
    var displayName: String
}

/// What to call an uploaded file and where to put it.
nonisolated struct UploadMetadata: Sendable {
    /// Folder relative to the app's root in the cloud, e.g. "Videos/2024/2024-07".
    var folderPath: String
    var filename: String
    var mimeType: String
    var createdAt: Date?
    var description: String
}
