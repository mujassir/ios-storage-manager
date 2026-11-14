import Foundation

/// Cloud services the app can move videos to. Raw values are persisted (CloudKit, manifest), never rename them.
nonisolated enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case googleDrive
    case oneDrive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .googleDrive: "Google Drive"
        case .oneDrive: "OneDrive"
        }
    }

    /// SF Symbol used as a badge in lists and the gallery.
    var symbolName: String {
        switch self {
        case .googleDrive: "externaldrive.fill.badge.icloud"
        case .oneDrive: "cloud.fill"
        }
    }

    var freeTierDescription: String {
        switch self {
        case .googleDrive: "15 GB free (shared with Gmail and Google Photos)"
        case .oneDrive: "5 GB free with a Microsoft account"
        }
    }
}

/// Which checksum a provider reports for uploaded files. Used to verify an upload before deleting the original.
nonisolated enum ChecksumKind: Sendable {
    /// Google Drive `md5Checksum`, lowercase hex.
    case md5Hex
    /// OneDrive `quickXorHash`, base64.
    case quickXorBase64
}
