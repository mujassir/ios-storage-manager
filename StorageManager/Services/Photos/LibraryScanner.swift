import Foundation
import Observation

/// Holds the latest scan of the Photos library for the Dashboard and Videos screens.
@Observable
final class LibraryScanner {
    private(set) var videos: [VideoAsset] = []
    private(set) var isScanning = false
    private(set) var lastScan: Date?
    private(set) var errorMessage: String?
    private(set) var deviceStorage = DeviceStorage.current()

    @ObservationIgnored private let photos: PhotoLibraryService

    init(photos: PhotoLibraryService) {
        self.photos = photos
    }

    var totalVideoBytes: Int64 { videos.reduce(0) { $0 + $1.sizeBytes } }
    var reclaimableBytes: Int64 { videos.filter(\.isLocallyAvailable).reduce(0) { $0 + $1.sizeBytes } }

    func bytes(matching filter: VideoFilter) -> Int64 {
        videos.filter(filter.matches).reduce(0) { $0 + $1.sizeBytes }
    }

    func count(matching filter: VideoFilter) -> Int {
        videos.filter(filter.matches).count
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            videos = try await photos.scanVideos()
            errorMessage = nil
            lastScan = .now
        } catch {
            errorMessage = error.localizedDescription
        }
        deviceStorage = DeviceStorage.current()
    }
}
