import Foundation
import AVFoundation

/// OneDrive via Microsoft Graph.
///
/// Uses the `Files.ReadWrite.AppFolder` scope: the app only gets its own folder
/// (`OneDrive/Apps/Storage Manager`), never the rest of the user's files.
final class OneDriveProvider: CloudProvider {
    let kind: ProviderKind = .oneDrive
    let account: AccountKey
    let checksumKind: ChecksumKind = .quickXorBase64

    private let http: AuthorizedHTTPClient

    /// Graph requires chunks to be a multiple of 320 KiB.
    static let chunkSize = 25 * 320 * 1024 // 7.8 MiB
    private static let graph = URL(string: "https://graph.microsoft.com/v1.0")!

    static func oauthConfiguration() throws -> OAuthConfiguration {
        let clientID = AppConfig.microsoftClientID
        guard !clientID.isEmpty else { throw OAuthError.notConfigured("OneDrive") }
        return OAuthConfiguration(
            authorizeURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
            tokenURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
            clientID: clientID,
            redirectURI: "msauth.\(AppConfig.bundleID)://auth",
            scopes: ["openid", "email", "offline_access", "User.Read", "Files.ReadWrite.AppFolder"]
        )
    }

    init(account: AccountKey, http: AuthorizedHTTPClient) {
        self.account = account
        self.http = http
    }

    // MARK: Account

    func fetchIdentity() async throws -> AccountIdentity {
        struct Me: Decodable { let id: String; let displayName: String?; let mail: String?; let userPrincipalName: String? }
        let me = try await http.json(Me.self, for: URLRequest(url: Self.graph.appending(path: "me")))
        let email = me.mail ?? me.userPrincipalName ?? ""
        return AccountIdentity(providerUserID: me.id, email: email, displayName: me.displayName ?? email)
    }

    func fetchQuota() async throws -> StorageQuota {
        struct Drive: Decodable { struct Quota: Decodable { let total: Int64?; let used: Int64? }; let quota: Quota? }
        let drive = try await http.json(Drive.self, for: URLRequest(url: Self.graph.appending(path: "me/drive")))
        return StorageQuota(totalBytes: drive.quota?.total ?? 0, usedBytes: drive.quota?.used ?? 0)
    }

    // MARK: Upload (upload session)

    func upload(fileURL: URL, metadata: UploadMetadata, progress: @escaping (Int64) -> Void) async throws -> RemoteFile {
        let totalSize = try FileHasher.fileSize(of: fileURL)
        let path = "\(metadata.folderPath)/\(metadata.filename)"

        var item: [String: Any] = ["@microsoft.graph.conflictBehavior": "rename"]
        if let createdAt = metadata.createdAt {
            let iso = ISO8601DateFormatter().string(from: createdAt)
            item["fileSystemInfo"] = ["createdDateTime": iso, "lastModifiedDateTime": iso]
        }
        struct Session: Decodable { let uploadUrl: String }
        let create = URLRequest(url: itemURL(path: path, action: "createUploadSession"), method: "POST", json: ["item": item])
        let session = try await withRetry { try await http.json(Session.self, for: create) }
        guard let uploadURL = URL(string: session.uploadUrl) else { throw HTTPError.invalidResponse }

        var offset: Int64 = 0
        var failures = 0
        while true {
            try Task.checkCancellation()
            await TransferThrottle.waitWhilePaused()
            do {
                let length = Int(min(Int64(Self.chunkSize), totalSize - offset))
                let chunkStart = offset
                let chunk = try await Task.detached { try FileHasher.readChunk(of: fileURL, offset: chunkStart, length: length) }.value
                var request = URLRequest(url: uploadURL)
                request.httpMethod = "PUT"
                request.setValue(String(chunk.count), forHTTPHeaderField: "Content-Length")
                request.setValue("bytes \(offset)-\(offset + Int64(chunk.count) - 1)/\(totalSize)", forHTTPHeaderField: "Content-Range")
                request.httpBody = chunk
                // The upload URL is pre-authorized; sending a bearer token to it is an error.
                let (data, response) = try await http.data(for: request, authorized: false)
                if response.statusCode == 202 {
                    offset = Self.nextOffset(fromUploadSession: data) ?? offset + Int64(chunk.count)
                    progress(offset)
                    failures = 0
                    continue
                }
                progress(totalSize)
                return try Self.remoteFile(from: data, folderPath: metadata.folderPath)
            } catch let error where !(error is CancellationError) && failures < 5 {
                failures += 1
                try await Task.sleep(for: .seconds(pow(2, Double(failures))))
                let (data, _) = try await http.data(for: URLRequest(url: uploadURL), authorized: false)
                offset = Self.nextOffset(fromUploadSession: data) ?? offset
                progress(offset)
            }
        }
    }

    /// Reads `nextExpectedRanges: ["26-"]` → 26.
    static func nextOffset(fromUploadSession data: Data) -> Int64? {
        struct Status: Decodable { let nextExpectedRanges: [String]? }
        guard let first = (try? JSONDecoder().decode(Status.self, from: data))?.nextExpectedRanges?.first,
              let start = first.split(separator: "-").first else { return nil }
        return Int64(start)
    }

    private static func remoteFile(from data: Data, folderPath: String) throws -> RemoteFile {
        struct Item: Decodable {
            struct File: Decodable { struct Hashes: Decodable { let quickXorHash: String? }; let hashes: Hashes? }
            let id: String; let name: String?; let size: Int64?; let file: File?
        }
        let item = try JSONDecoder.api.decode(Item.self, from: data)
        return RemoteFile(
            id: item.id,
            path: "\(folderPath)/\(item.name ?? "")",
            sizeBytes: item.size ?? 0,
            checksum: item.file?.hashes?.quickXorHash ?? ""
        )
    }

    func fileInfo(for file: RemoteFile) async throws -> RemoteFile {
        let (data, _) = try await http.data(for: URLRequest(url: Self.graph.appending(path: "me/drive/items/\(file.id)")))
        return try Self.remoteFile(from: data, folderPath: (file.path as NSString).deletingLastPathComponent)
    }

    // MARK: Download, delete, play

    /// Graph returns a short-lived, pre-authenticated download URL that AVPlayer and URLSession can use directly.
    private func downloadURL(for file: RemoteFile) async throws -> URL {
        try await downloadURL(fromItemAt: Self.graph.appending(path: "me/drive/items/\(file.id)"))
    }

    private func downloadURL(fromItemAt itemURL: URL) async throws -> URL {
        let (data, _) = try await http.data(for: URLRequest(url: itemURL))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let link = object["@microsoft.graph.downloadUrl"] as? String,
              let url = URL(string: link) else { throw CloudProviderError.missingDownloadURL }
        return url
    }

    func download(_ file: RemoteFile, to destination: URL) async throws {
        try await http.download(URLRequest(url: try await downloadURL(for: file)), to: destination, authorized: false)
    }

    func delete(_ file: RemoteFile) async throws {
        _ = try await http.data(for: URLRequest(url: Self.graph.appending(path: "me/drive/items/\(file.id)"), method: "DELETE"), acceptedStatus: [404])
    }

    func playableMedia(for file: RemoteFile, filename: String) async throws -> PlayableMedia {
        PlayableMedia(asset: AVURLAsset(url: try await downloadURL(for: file)), retainedObjects: [])
    }

    // MARK: Sharing

    func createShareLink(for file: RemoteFile) async throws -> ShareLinkInfo {
        struct Permission: Decodable { struct Link: Decodable { let webUrl: String }; let id: String; let link: Link }
        let request = URLRequest(url: Self.graph.appending(path: "me/drive/items/\(file.id)/createLink"), method: "POST",
                                 json: ["type": "view", "scope": "anonymous"])
        let permission = try await http.json(Permission.self, for: request)
        guard let url = URL(string: permission.link.webUrl) else { throw CloudProviderError.missingDownloadURL }
        return ShareLinkInfo(url: url, permissionID: permission.id)
    }

    func removeShareLink(permissionID: String, for file: RemoteFile) async throws {
        let url = Self.graph.appending(path: "me/drive/items/\(file.id)/permissions/\(permissionID)")
        _ = try await http.data(for: URLRequest(url: url, method: "DELETE"), acceptedStatus: [404])
    }

    // MARK: Manifest

    func readManifest() async throws -> CatalogManifest? {
        do {
            // Fetch via the pre-signed link; the `/content` redirect must not carry our bearer token.
            let link = try await downloadURL(fromItemAt: itemURL(path: AppConfig.manifestFilename, action: nil))
            let (data, _) = try await http.data(for: URLRequest(url: link), authorized: false)
            return try CatalogManifest.decode(data)
        } catch let error as HTTPError where error.statusCode == 404 {
            return nil
        }
    }

    func writeManifest(_ manifest: CatalogManifest) async throws {
        var request = URLRequest(url: itemURL(path: AppConfig.manifestFilename, action: "content"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try manifest.encoded()
        _ = try await withRetry { try await http.data(for: request) }
    }

    // MARK: Paths

    /// `/me/drive/special/approot:/Videos/2024/file.mov:/createUploadSession`, or the item itself when `action` is nil.
    private func itemURL(path: String, action: String?) -> URL {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: ":#?")
        let encoded = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }.joined(separator: "/")
        let base = "\(Self.graph.absoluteString)/me/drive/special/approot:/\(encoded)"
        return URL(string: action.map { "\(base):/\($0)" } ?? base)!
    }
}
