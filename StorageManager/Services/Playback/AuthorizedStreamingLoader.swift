import Foundation
import AVFoundation

/// Streams a video that needs an `Authorization` header (Google Drive) into AVPlayer.
///
/// AVPlayer can't add headers itself, so the asset uses a custom URL scheme. AVFoundation then asks this
/// delegate for each byte range; it fetches that range from the real URL with a bearer token. Seeking works
/// because every request is an HTTP Range request.
nonisolated final class AuthorizedStreamingLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "smstream"
    private static let maxBytesPerRequest: Int64 = 4 * 1024 * 1024

    private let sourceURL: URL
    private let contentLength: Int64
    private let contentType: String
    private let tokenProvider: @Sendable () async throws -> String
    private let session: URLSession
    private let queue = DispatchQueue(label: "StorageManager.streaming")
    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(sourceURL: URL, contentLength: Int64, contentType: String,
         tokenProvider: @escaping @Sendable () async throws -> String, session: URLSession = .shared) {
        self.sourceURL = sourceURL
        self.contentLength = contentLength
        self.contentType = contentType
        self.tokenProvider = tokenProvider
        self.session = session
    }

    func makeAsset() -> AVURLAsset {
        var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)!
        components.scheme = Self.scheme
        let asset = AVURLAsset(url: components.url!)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return asset
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        let key = ObjectIdentifier(loadingRequest)
        let box = UncheckedSendableBox(loadingRequest)
        let task = Task { [weak self] in
            await self?.handle(box.value)
            self?.removeTask(key)
        }
        lock.withLock { tasks[key] = task }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        let key = ObjectIdentifier(loadingRequest)
        lock.withLock { tasks.removeValue(forKey: key) }?.cancel()
    }

    private func removeTask(_ key: ObjectIdentifier) {
        lock.withLock { _ = tasks.removeValue(forKey: key) }
    }

    private func handle(_ request: AVAssetResourceLoadingRequest) async {
        if let info = request.contentInformationRequest {
            info.contentType = contentType
            info.contentLength = contentLength
            info.isByteRangeAccessSupported = true
        }
        guard let dataRequest = request.dataRequest else {
            request.finishLoading()
            return
        }

        var offset = dataRequest.currentOffset != 0 ? dataRequest.currentOffset : dataRequest.requestedOffset
        let end: Int64 = dataRequest.requestsAllDataToEndOfResource
            ? contentLength
            : min(contentLength, dataRequest.requestedOffset + Int64(dataRequest.requestedLength))

        do {
            while offset < end {
                try Task.checkCancellation()
                let chunkEnd = min(end, offset + Self.maxBytesPerRequest) - 1
                var urlRequest = URLRequest(url: sourceURL)
                urlRequest.setValue("bytes=\(offset)-\(chunkEnd)", forHTTPHeaderField: "Range")
                urlRequest.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
                let (data, response) = try await session.data(for: urlRequest)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
                    throw HTTPError.status((response as? HTTPURLResponse)?.statusCode ?? 0, "Streaming failed")
                }
                dataRequest.respond(with: data)
                offset += Int64(data.count)
            }
            request.finishLoading()
        } catch is CancellationError {
            // AVFoundation cancelled this request (e.g. the user seeked); nothing to report.
        } catch {
            request.finishLoading(with: error)
        }
    }
}

/// Carries a non-Sendable AVFoundation object across a concurrency boundary when we know
/// AVFoundation itself synchronizes access to it.
nonisolated struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
