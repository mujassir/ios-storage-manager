import Foundation
import SwiftData
import CoreLocation

/// One video that was moved off the phone. This is the catalog the gallery is built from.
/// Synced through CloudKit, and mirrored into a manifest file inside each cloud account.
@Model
final class MovedVideo {
    var catalogID: UUID = UUID()
    var originalFilename: String = ""
    /// Short human title, generated on-device (Apple Intelligence) or from place/date as a fallback.
    var title: String = ""
    /// Reverse-geocoded place name, e.g. "Santa Monica".
    var placeName: String = ""
    /// Space-separated scene labels from Vision ("beach ocean sunset"), used by search.
    var keywords: String = ""
    var sizeBytes: Int64 = 0
    var durationSeconds: Double = 0
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    /// Original capture date from Photos, so a restore lands at the right spot on the timeline.
    var createdAt: Date?
    var latitude: Double?
    var longitude: Double?
    /// Original `PHAsset.localIdentifier`. Only meaningful on the device it came from.
    var originalAssetIdentifier: String = ""

    var providerRaw: String = ProviderKind.googleDrive.rawValue
    var providerUserID: String = ""
    var remoteFileID: String = ""
    var remotePath: String = ""
    /// Provider-native checksum used to verify the upload (Drive: MD5 hex, OneDrive: QuickXorHash base64).
    var checksum: String = ""
    var movedAt: Date = Date.now
    /// Whether the original was removed from the phone after a verified upload.
    var deletedFromDevice: Bool = false
    /// The cloud reported the same size and checksum as the original.
    var isVerified: Bool = false
    /// Public "anyone with the link" URL, if the user shared this video.
    var shareURLString: String = ""
    /// Provider permission ID backing the share link, used to stop sharing.
    var sharePermissionID: String = ""

    /// Small JPEG (~30 KB) so the gallery works on a new device before any account is reconnected.
    @Attribute(.externalStorage) var thumbnailJPEG: Data?

    init(
        originalFilename: String,
        title: String,
        placeName: String,
        keywords: String,
        sizeBytes: Int64,
        durationSeconds: Double,
        pixelWidth: Int,
        pixelHeight: Int,
        createdAt: Date?,
        location: CLLocation?,
        originalAssetIdentifier: String,
        provider: ProviderKind,
        providerUserID: String,
        remoteFileID: String,
        remotePath: String,
        checksum: String,
        thumbnailJPEG: Data?
    ) {
        self.originalFilename = originalFilename
        self.title = title
        self.placeName = placeName
        self.keywords = keywords
        self.sizeBytes = sizeBytes
        self.durationSeconds = durationSeconds
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.createdAt = createdAt
        self.latitude = location?.coordinate.latitude
        self.longitude = location?.coordinate.longitude
        self.originalAssetIdentifier = originalAssetIdentifier
        self.providerRaw = provider.rawValue
        self.providerUserID = providerUserID
        self.remoteFileID = remoteFileID
        self.remotePath = remotePath
        self.checksum = checksum
        self.thumbnailJPEG = thumbnailJPEG
    }

    var provider: ProviderKind { ProviderKind(rawValue: providerRaw) ?? .googleDrive }
    var accountKey: AccountKey { AccountKey(provider: provider, providerUserID: providerUserID) }

    var location: CLLocation? {
        guard let latitude, let longitude else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }

    var displayTitle: String { title.isEmpty ? originalFilename : title }

    var shareURL: URL? { shareURLString.isEmpty ? nil : URL(string: shareURLString) }

    /// Verified in the cloud but still taking space on this phone.
    var isPendingCleanup: Bool { isVerified && !deletedFromDevice && !originalAssetIdentifier.isEmpty }

    var remoteFile: RemoteFile {
        RemoteFile(id: remoteFileID, path: remotePath, sizeBytes: sizeBytes, checksum: checksum)
    }
}
