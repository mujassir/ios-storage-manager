import Foundation
import AVFoundation

/// Something AVPlayer can play, plus whatever must stay alive while it plays
/// (AVAssetResourceLoader only keeps a weak reference to its delegate).
struct PlayableMedia {
    let asset: AVURLAsset
    let retainedObjects: [AnyObject]
}

/// One connected cloud account. Each provider adapts its own REST API to this interface,
/// so the transfer engine, player and gallery never care where a video lives.
protocol CloudProvider: AnyObject {
    var kind: ProviderKind { get }
    var account: AccountKey { get }
    var checksumKind: ChecksumKind { get }

    func fetchIdentity() async throws -> AccountIdentity
    func fetchQuota() async throws -> StorageQuota

    /// Uploads a local file with a resumable, chunked upload. `progress` reports total bytes sent.
    func upload(fileURL: URL, metadata: UploadMetadata, progress: @escaping (Int64) -> Void) async throws -> RemoteFile
    func fileInfo(for file: RemoteFile) async throws -> RemoteFile
    func download(_ file: RemoteFile, to destination: URL) async throws
    func delete(_ file: RemoteFile) async throws
    func playableMedia(for file: RemoteFile, filename: String) async throws -> PlayableMedia

    func readManifest() async throws -> CatalogManifest?
    func writeManifest(_ manifest: CatalogManifest) async throws
}

/// Errors any provider may throw that the UI explains specially.
enum CloudProviderError: LocalizedError {
    case notEnoughSpace
    case uploadIncomplete
    case missingDownloadURL

    var errorDescription: String? {
        switch self {
        case .notEnoughSpace: "Not enough free space in your connected clouds."
        case .uploadIncomplete: "The upload didn't finish. It will be retried."
        case .missingDownloadURL: "The cloud didn't provide a playable link."
        }
    }
}
