import Foundation
import Photos

/// A video in the user's Photos library, as plain Sendable values (the scan runs off the main thread).
/// Look up the live `PHAsset` with `PhotoLibraryService.asset(for:)` when needed.
nonisolated struct VideoAsset: Identifiable, Hashable, Sendable {
    let id: String              // PHAsset.localIdentifier
    let filename: String
    let sizeBytes: Int64
    let durationSeconds: Double
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
    let latitude: Double?
    let longitude: Double?
    let isScreenRecording: Bool
    let isFavorite: Bool
    /// False when iCloud Photos "Optimize Storage" keeps only a preview on the phone.
    /// Moving such a video frees almost no space.
    let isLocallyAvailable: Bool

    var location: CLLocation? {
        guard let latitude, let longitude else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }

    func isOlder(thanYears years: Int, now: Date = .now) -> Bool {
        guard let creationDate, let cutoff = Calendar.current.date(byAdding: .year, value: -years, to: now) else { return false }
        return creationDate < cutoff
    }
}

/// Quick filters on the Videos screen.
nonisolated enum VideoFilter: String, CaseIterable, Identifiable, Sendable {
    case all, large, old, screenRecordings, onPhoneOnly

    static let largeThreshold: Int64 = 500 * 1024 * 1024

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .large: "Large"
        case .old: "Over 1 Year"
        case .screenRecordings: "Screen Recordings"
        case .onPhoneOnly: "Frees Space"
        }
    }

    func matches(_ video: VideoAsset) -> Bool {
        switch self {
        case .all: true
        case .large: video.sizeBytes >= Self.largeThreshold
        case .old: video.isOlder(thanYears: 1)
        case .screenRecordings: video.isScreenRecording
        case .onPhoneOnly: video.isLocallyAvailable
        }
    }
}
