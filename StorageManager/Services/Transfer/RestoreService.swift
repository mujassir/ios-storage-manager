import Foundation
import SwiftData
import Observation

/// Brings videos back from the cloud into Photos, at their original date and location.
@Observable
final class RestoreService {
    enum State: Equatable {
        case downloading
        case saving
        case restored
        case failed(String)
    }

    private(set) var states: [UUID: State] = [:]

    @ObservationIgnored private let photos: PhotoLibraryService
    @ObservationIgnored private let accounts: AccountManager

    init(photos: PhotoLibraryService, accounts: AccountManager) {
        self.photos = photos
        self.accounts = accounts
    }

    var isBusy: Bool { states.values.contains { $0 == .downloading || $0 == .saving } }

    func restore(_ videos: [MovedVideo], deleteCloudCopy: Bool, context: ModelContext) async {
        var removedByAccount: [AccountKey: Set<UUID>] = [:]
        for video in videos {
            let id = video.catalogID
            states[id] = .downloading
            do {
                let provider = try accounts.requireProvider(for: video.accountKey)
                let directory = FileManager.default.temporaryDirectory.appending(path: "Restore/\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let fileURL = directory.appending(path: CloudPaths.sanitize(video.originalFilename).isEmpty ? "video.mov" : CloudPaths.sanitize(video.originalFilename))
                try await provider.download(video.remoteFile, to: fileURL)

                states[id] = .saving
                let newIdentifier = try await photos.saveVideoToLibrary(
                    fileURL: fileURL, originalFilename: video.originalFilename,
                    creationDate: video.createdAt, latitude: video.latitude, longitude: video.longitude
                )

                if deleteCloudCopy {
                    try await provider.delete(video.remoteFile)
                    removedByAccount[video.accountKey, default: []].insert(id)
                    context.delete(video)
                } else {
                    video.deletedFromDevice = false
                    video.originalAssetIdentifier = newIdentifier ?? video.originalAssetIdentifier
                }
                try context.save()
                states[id] = .restored
            } catch {
                states[id] = .failed(error.localizedDescription)
            }
        }
        for (key, removed) in removedByAccount {
            try? await accounts.syncManifest(for: key, removing: removed, context: context)
        }
    }

    func clear(_ id: UUID) { states[id] = nil }
}
