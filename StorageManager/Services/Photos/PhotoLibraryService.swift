import Foundation
import Photos
import UIKit
import Observation

enum PhotoLibraryError: LocalizedError {
    case notAuthorized
    case assetNotFound
    case noVideoResource
    case thumbnailFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "Storage Manager needs access to your Photos library. You can allow it in Settings."
        case .assetNotFound: "This video is no longer in your Photos library."
        case .noVideoResource: "Couldn't read the original video file."
        case .thumbnailFailed: "Couldn't create a thumbnail."
        }
    }
}

/// Everything the app does with PhotoKit.
@Observable
final class PhotoLibraryService {
    @ObservationIgnored private let imageManager = PHCachingImageManager()

    // MARK: Authorization

    var authorizationStatus: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    // MARK: Scan

    /// Lists every video with its real file size, largest first. Runs off the main thread.
    func scanVideos() async throws -> [VideoAsset] {
        let status = authorizationStatus
        guard status == .authorized || status == .limited else { throw PhotoLibraryError.notAuthorized }
        return await Task.detached(priority: .userInitiated) { Self.scanSynchronously() }.value
    }

    nonisolated private static func scanSynchronously() -> [VideoAsset] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        let result = PHAsset.fetchAssets(with: .video, options: options)
        var videos: [VideoAsset] = []
        videos.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            videos.append(makeVideoAsset(from: asset))
        }
        return videos.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    nonisolated private static func makeVideoAsset(from asset: PHAsset) -> VideoAsset {
        let resource = primaryVideoResource(for: asset)
        // `fileSize` and `locallyAvailable` aren't public properties, but are the only way to read the real
        // size without downloading. Fall back to an estimate (≈ 1.5 MB/s, typical 1080p HEVC).
        let size = (resource?.value(forKey: "fileSize") as? NSNumber)?.int64Value
            ?? Int64(asset.duration * 1_500_000)
        let local = (resource?.value(forKey: "locallyAvailable") as? NSNumber)?.boolValue ?? true
        return VideoAsset(
            id: asset.localIdentifier,
            filename: resource?.originalFilename ?? "Video.mov",
            sizeBytes: size,
            durationSeconds: asset.duration,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            creationDate: asset.creationDate,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude,
            isScreenRecording: asset.mediaSubtypes.contains(.videoScreenRecording),
            isFavorite: asset.isFavorite,
            isLocallyAvailable: local
        )
    }

    /// The edited version if there is one (that's what the user sees in Photos), otherwise the original.
    nonisolated static func primaryVideoResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first { $0.type == .fullSizeVideo }
            ?? resources.first { $0.type == .video }
            ?? resources.first { $0.type == .pairedVideo }
    }

    func asset(for identifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    // MARK: Export original

    /// Writes the original video bytes (no re-encoding, metadata intact) to `directory`.
    /// Downloads from iCloud first if needed.
    func exportOriginal(_ video: VideoAsset, to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let asset = asset(for: video.id) else { throw PhotoLibraryError.assetNotFound }
        guard let resource = Self.primaryVideoResource(for: asset) else { throw PhotoLibraryError.noVideoResource }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: CloudPaths.sanitize(resource.originalFilename).isEmpty ? "video.mov" : CloudPaths.sanitize(resource.originalFilename))
        try? FileManager.default.removeItem(at: destination)

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        options.progressHandler = { @Sendable fraction in progress(fraction) }
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options)
        return destination
    }

    // MARK: Thumbnails

    func thumbnail(for identifier: String, size: CGSize) async -> UIImage? {
        guard let asset = asset(for: identifier) else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let once = OnceFlag()
        return await withCheckedContinuation { continuation in
            imageManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { @Sendable image, info in
                // Opportunistic delivery calls back first with a blurry preview; wait for the final image.
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !degraded || image == nil, once.claim() else { return }
                continuation.resume(returning: image)
            }
        }
    }

    /// Small JPEG stored in the catalog (synced via CloudKit, so keep it ~30 KB).
    func catalogThumbnailJPEG(for identifier: String) async -> Data? {
        await thumbnail(for: identifier, size: CGSize(width: 360, height: 360))?.jpegData(compressionQuality: 0.6)
    }

    // MARK: Delete & restore

    /// Deletes videos in one batch, so the user sees a single iOS confirmation.
    /// iOS moves them to Recently Deleted; space is freed once that album is emptied (or after 30 days).
    func deleteVideos(withIdentifiers identifiers: [String]) async throws {
        guard !identifiers.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            PHAssetChangeRequest.deleteAssets(assets)
        }
    }

    /// Saves a downloaded video back into Photos at its original date and location.
    /// Returns the new asset's local identifier.
    @discardableResult
    func saveVideoToLibrary(fileURL: URL, originalFilename: String, creationDate: Date?, latitude: Double?, longitude: Double?) async throws -> String? {
        let status = authorizationStatus
        guard status == .authorized || status == .limited else { throw PhotoLibraryError.notAuthorized }
        let identifierBox = IdentifierBox()
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            let request = PHAssetCreationRequest.forAsset()
            request.creationDate = creationDate
            if let latitude, let longitude {
                request.location = CLLocation(latitude: latitude, longitude: longitude)
            }
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = originalFilename
            options.shouldMoveFile = true
            request.addResource(with: .video, fileURL: fileURL, options: options)
            identifierBox.value = request.placeholderForCreatedAsset?.localIdentifier
        }
        return identifierBox.value
    }
}

/// Passes the placeholder identifier out of PhotoKit's change block.
nonisolated private final class IdentifierBox: @unchecked Sendable {
    var value: String?
}

/// Makes sure a continuation is resumed exactly once from a callback that may fire several times.
nonisolated final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            if claimed { return false }
            claimed = true
            return true
        }
    }
}
