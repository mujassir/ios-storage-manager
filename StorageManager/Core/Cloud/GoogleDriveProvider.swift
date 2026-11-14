import Foundation
import AVFoundation

/// Google Drive via the Drive v3 REST API.
///
/// Uses the `drive.file` scope: the app can only see files it created itself, which is all it needs and
/// is far easier to get through Google's OAuth verification than full Drive access. Files created on one
/// device stay visible to the same app on a new device, because access is tied to the OAuth client.
final class GoogleDriveProvider: CloudProvider {
    let kind: ProviderKind = .googleDrive
    let account: AccountKey
    let checksumKind: ChecksumKind = .md5Hex

    private let http: AuthorizedHTTPClient
    private var folderIDs: [String: String] = [:]

    /// Must be a multiple of 256 KiB.
    static let chunkSize = 32 * 256 * 1024 // 8 MiB
    private static let api = URL(string: "https://www.googleapis.com/drive/v3")!
    private static let uploadAPI = URL(string: "https://www.googleapis.com/upload/drive/v3")!
    private static let folderMimeType = "application/vnd.google-apps.folder"
    private static let fileFields = "id,name,size,md5Checksum"

    static func oauthConfiguration() throws -> OAuthConfiguration {
        let clientID = AppConfig.googleClientID
        guard !clientID.isEmpty else { throw OAuthError.notConfigured("Google Drive") }
        // iOS OAuth clients redirect to the reversed client ID.
        let reversed = clientID.split(separator: ".").reversed().joined(separator: ".")
        return OAuthConfiguration(
            authorizeURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            clientID: clientID,
            redirectURI: "\(reversed):/oauthredirect",
            scopes: ["openid", "email", "profile", "https://www.googleapis.com/auth/drive.file"]
        )
    }

    init(account: AccountKey, http: AuthorizedHTTPClient) {
        self.account = account
        self.http = http
    }

    // MARK: Account

    func fetchIdentity() async throws -> AccountIdentity {
        struct UserInfo: Decodable { let sub: String; let email: String?; let name: String? }
        let info = try await http.json(UserInfo.self, for: URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!))
        return AccountIdentity(providerUserID: info.sub, email: info.email ?? "", displayName: info.name ?? info.email ?? "Google account")
    }

    func fetchQuota() async throws -> StorageQuota {
        struct About: Decodable {
            struct Quota: Decodable { let limit: String?; let usage: String? }
            let storageQuota: Quota
        }
        let url = Self.api.appending(path: "about").appending(queryItems: [URLQueryItem(name: "fields", value: "storageQuota")])
        let about = try await http.json(About.self, for: URLRequest(url: url))
        // No limit means an unlimited plan; report a large total so the allocator still works.
        let total = Int64(about.storageQuota.limit ?? "") ?? Int64.max / 4
        return StorageQuota(totalBytes: total, usedBytes: Int64(about.storageQuota.usage ?? "") ?? 0)
    }

    // MARK: Upload (resumable protocol)

    func upload(fileURL: URL, metadata: UploadMetadata, progress: @escaping (Int64) -> Void) async throws -> RemoteFile {
        let totalSize = try FileHasher.fileSize(of: fileURL)
        let parentID = try await folderID(forPath: "\(AppConfig.cloudRootFolderName)/\(metadata.folderPath)")

        // 1. Start a resumable session.
        var body: [String: Any] = [
            "name": metadata.filename,
            "parents": [parentID],
            "mimeType": metadata.mimeType,
            "description": metadata.description,
        ]
        if let createdAt = metadata.createdAt {
            body["createdTime"] = ISO8601DateFormatter().string(from: createdAt)
        }
        let startURL = Self.uploadAPI.appending(path: "files").appending(queryItems: [
            URLQueryItem(name: "uploadType", value: "resumable"),
            URLQueryItem(name: "fields", value: Self.fileFields),
        ])
        var start = URLRequest(url: startURL, method: "POST", json: body)
        start.setValue(metadata.mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        start.setValue(String(totalSize), forHTTPHeaderField: "X-Upload-Content-Length")
        let (_, startResponse) = try await withRetry { try await http.data(for: start) }
        guard let location = startResponse.value(forHTTPHeaderField: "Location"), let sessionURL = URL(string: location) else {
            throw HTTPError.invalidResponse
        }

        // 2. Send chunks. On any failure, ask the server how much it has and continue from there.
        var offset: Int64 = 0
        var failures = 0
        while true {
            try Task.checkCancellation()
            await TransferThrottle.waitWhilePaused()
            do {
                let length = Int(min(Int64(Self.chunkSize), totalSize - offset))
                let chunkStart = offset
                let chunk = try await Task.detached { try FileHasher.readChunk(of: fileURL, offset: chunkStart, length: length) }.value
                var request = URLRequest(url: sessionURL)
                request.httpMethod = "PUT"
                request.setValue(String(chunk.count), forHTTPHeaderField: "Content-Length")
                if totalSize > 0 {
                    request.setValue("bytes \(offset)-\(offset + Int64(chunk.count) - 1)/\(totalSize)", forHTTPHeaderField: "Content-Range")
                }
                request.httpBody = chunk
                let (data, response) = try await http.data(for: request, acceptedStatus: [308])
                if response.statusCode == 308 {
                    offset = Self.nextOffset(fromRangeHeader: response.value(forHTTPHeaderField: "Range"))
                    progress(offset)
                    failures = 0
                    continue
                }
                progress(totalSize)
                return try Self.remoteFile(from: data, folderPath: metadata.folderPath)
            } catch let error where !(error is CancellationError) && failures < 5 {
                failures += 1
                try await Task.sleep(for: .seconds(pow(2, Double(failures))))
                offset = try await uploadedBytes(sessionURL: sessionURL, totalSize: totalSize)
                progress(offset)
            }
        }
    }

    /// Asks a resumable session how many bytes it has received.
    private func uploadedBytes(sessionURL: URL, totalSize: Int64) async throws -> Int64 {
        var request = URLRequest(url: sessionURL)
        request.httpMethod = "PUT"
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        request.setValue("bytes */\(totalSize)", forHTTPHeaderField: "Content-Range")
        let (_, response) = try await http.data(for: request, acceptedStatus: [308])
        return response.statusCode == 308 ? Self.nextOffset(fromRangeHeader: response.value(forHTTPHeaderField: "Range")) : totalSize
    }

    /// "bytes=0-1048575" → 1048576. A missing header means nothing was received yet.
    static func nextOffset(fromRangeHeader header: String?) -> Int64 {
        guard let header, let last = header.split(separator: "-").last, let end = Int64(last) else { return 0 }
        return end + 1
    }

    private static func remoteFile(from data: Data, folderPath: String) throws -> RemoteFile {
        struct File: Decodable { let id: String; let name: String?; let size: String?; let md5Checksum: String? }
        let file = try JSONDecoder.api.decode(File.self, from: data)
        return RemoteFile(
            id: file.id,
            path: "\(folderPath)/\(file.name ?? "")",
            sizeBytes: Int64(file.size ?? "") ?? 0,
            checksum: file.md5Checksum ?? ""
        )
    }

    func fileInfo(for file: RemoteFile) async throws -> RemoteFile {
        let url = Self.api.appending(path: "files/\(file.id)").appending(queryItems: [URLQueryItem(name: "fields", value: Self.fileFields)])
        let (data, _) = try await http.data(for: URLRequest(url: url))
        let folder = (file.path as NSString).deletingLastPathComponent
        return try Self.remoteFile(from: data, folderPath: folder)
    }

    // MARK: Download, delete, play

    func download(_ file: RemoteFile, to destination: URL) async throws {
        try await http.download(URLRequest(url: mediaURL(for: file.id)), to: destination)
    }

    func delete(_ file: RemoteFile) async throws {
        _ = try await http.data(for: URLRequest(url: Self.api.appending(path: "files/\(file.id)"), method: "DELETE"), acceptedStatus: [404])
    }

    func playableMedia(for file: RemoteFile, filename: String) async throws -> PlayableMedia {
        let loader = AuthorizedStreamingLoader(
            sourceURL: mediaURL(for: file.id),
            contentLength: file.sizeBytes,
            contentType: CloudPaths.uniformTypeIdentifier(forFilename: filename),
            tokenProvider: { [http] in try await http.tokens.validAccessToken() }
        )
        return PlayableMedia(asset: loader.makeAsset(), retainedObjects: [loader])
    }

    private func mediaURL(for fileID: String) -> URL {
        Self.api.appending(path: "files/\(fileID)").appending(queryItems: [URLQueryItem(name: "alt", value: "media")])
    }

    // MARK: Sharing

    func createShareLink(for file: RemoteFile) async throws -> ShareLinkInfo {
        struct Permission: Decodable { let id: String }
        struct Link: Decodable { let webViewLink: String? }
        let permissionURL = Self.api.appending(path: "files/\(file.id)/permissions").appending(queryItems: [URLQueryItem(name: "fields", value: "id")])
        let permission = try await http.json(Permission.self, for: URLRequest(url: permissionURL, method: "POST", json: ["role": "reader", "type": "anyone"]))
        let linkURL = Self.api.appending(path: "files/\(file.id)").appending(queryItems: [URLQueryItem(name: "fields", value: "webViewLink")])
        guard let link = try await http.json(Link.self, for: URLRequest(url: linkURL)).webViewLink, let url = URL(string: link) else {
            throw CloudProviderError.missingDownloadURL
        }
        return ShareLinkInfo(url: url, permissionID: permission.id)
    }

    func removeShareLink(permissionID: String, for file: RemoteFile) async throws {
        let url = Self.api.appending(path: "files/\(file.id)/permissions/\(permissionID)")
        _ = try await http.data(for: URLRequest(url: url, method: "DELETE"), acceptedStatus: [404])
    }

    // MARK: Manifest

    func readManifest() async throws -> CatalogManifest? {
        guard let rootID = try await existingFolderID(named: AppConfig.cloudRootFolderName, parent: "root"),
              let fileID = try await findChild(named: AppConfig.manifestFilename, parent: rootID, mimeType: nil) else { return nil }
        let (data, _) = try await http.data(for: URLRequest(url: mediaURL(for: fileID)))
        return try CatalogManifest.decode(data)
    }

    func writeManifest(_ manifest: CatalogManifest) async throws {
        let rootID = try await folderID(forPath: AppConfig.cloudRootFolderName)
        let data = try manifest.encoded()
        let fileID: String
        if let existing = try await findChild(named: AppConfig.manifestFilename, parent: rootID, mimeType: nil) {
            fileID = existing
        } else {
            struct Created: Decodable { let id: String }
            let create = URLRequest(url: Self.api.appending(path: "files"), method: "POST", json: [
                "name": AppConfig.manifestFilename, "parents": [rootID], "mimeType": "application/json",
            ])
            fileID = try await http.json(Created.self, for: create).id
        }
        var update = URLRequest(url: Self.uploadAPI.appending(path: "files/\(fileID)").appending(queryItems: [URLQueryItem(name: "uploadType", value: "media")]))
        update.httpMethod = "PATCH"
        update.setValue("application/json", forHTTPHeaderField: "Content-Type")
        update.httpBody = data
        _ = try await withRetry { try await http.data(for: update) }
    }

    // MARK: Folders

    /// Finds or creates each folder along a path like "Storage Manager/Videos/2024/2024-07".
    private func folderID(forPath path: String) async throws -> String {
        if let cached = folderIDs[path] { return cached }
        var parent = "root"
        var walked: [String] = []
        for name in path.split(separator: "/").map(String.init) {
            walked.append(name)
            let key = walked.joined(separator: "/")
            if let cached = folderIDs[key] { parent = cached; continue }
            let id: String
            if let existing = try await existingFolderID(named: name, parent: parent) {
                id = existing
            } else {
                struct Created: Decodable { let id: String }
                let create = URLRequest(url: Self.api.appending(path: "files"), method: "POST", json: [
                    "name": name, "parents": [parent], "mimeType": Self.folderMimeType,
                ])
                id = try await http.json(Created.self, for: create).id
            }
            folderIDs[key] = id
            parent = id
        }
        return parent
    }

    private func existingFolderID(named name: String, parent: String) async throws -> String? {
        try await findChild(named: name, parent: parent, mimeType: Self.folderMimeType)
    }

    private func findChild(named name: String, parent: String, mimeType: String?) async throws -> String? {
        struct List: Decodable { struct File: Decodable { let id: String }; let files: [File] }
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        var query = "name = '\(escaped)' and '\(parent)' in parents and trashed = false"
        if let mimeType { query += " and mimeType = '\(mimeType)'" }
        let url = Self.api.appending(path: "files").appending(queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id)"),
            URLQueryItem(name: "spaces", value: "drive"),
        ])
        return try await http.json(List.self, for: URLRequest(url: url)).files.first?.id
    }
}
