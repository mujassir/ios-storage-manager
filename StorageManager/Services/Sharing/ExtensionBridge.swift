import Foundation
import SwiftData
import FileProvider
import WidgetKit

/// Keeps the Files extension and the widgets up to date: writes the shared snapshot and thumbnails into the
/// App Group, registers the "Storage Manager" location in Files, and tells both extensions to refresh.
final class ExtensionBridge {
    private var generation: Int
    private var domainRegistered = false

    init() {
        generation = LibrarySnapshot.load()?.generation ?? 0
    }

    static var fileProviderDomain: NSFileProviderDomain {
        NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(rawValue: AppConfig.fileProviderDomainID),
                             displayName: "Storage Manager")
    }

    /// Adds the Storage Manager location to the Files app (idempotent).
    func registerFileProviderDomain() async {
        guard !domainRegistered else { return }
        do {
            try await NSFileProviderManager.add(Self.fileProviderDomain)
            domainRegistered = true
        } catch {
            // Usually means the extension isn't embedded/signed in this build. The app works without it.
        }
    }

    func refresh(context: ModelContext, scanner: LibraryScanner, accounts: AccountManager) {
        let linked = (try? context.fetch(FetchDescriptor<LinkedAccount>())) ?? []
        let moved = (try? context.fetch(FetchDescriptor<MovedVideo>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        let onDevice = Dictionary(scanner.videos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pending = moved.filter { $0.isPendingCleanup && onDevice[$0.originalAssetIdentifier] != nil }

        generation += 1
        let snapshot = LibrarySnapshot(
            generation: generation,
            generatedAt: .now,
            accounts: linked.map { account in
                let quota = accounts.quota(for: account)
                return .init(provider: account.provider, providerUserID: account.providerUserID, email: account.email,
                             totalBytes: quota?.totalBytes ?? 0, usedBytes: quota?.usedBytes ?? 0,
                             isConnected: accounts.isConnected(account))
            },
            videos: moved.map { video in
                .init(catalogID: video.catalogID, title: video.title, originalFilename: video.originalFilename,
                      sizeBytes: video.sizeBytes, durationSeconds: video.durationSeconds, createdAt: video.createdAt,
                      movedAt: video.movedAt, provider: video.provider, providerUserID: video.providerUserID,
                      remoteFileID: video.remoteFileID, remotePath: video.remotePath, checksum: video.checksum,
                      deletedFromDevice: video.deletedFromDevice)
            },
            phone: .init(
                videoCount: scanner.videos.count,
                videoBytes: scanner.totalVideoBytes,
                reclaimableBytes: scanner.reclaimableBytes,
                pendingCleanupCount: pending.count,
                pendingCleanupBytes: pending.reduce(0) { $0 + $1.sizeBytes },
                lastScan: scanner.lastScan
            )
        )
        try? snapshot.save()
        writeThumbnails(for: moved)

        WidgetCenter.shared.reloadAllTimelines()
        Task {
            await registerFileProviderDomain()
            try? await NSFileProviderManager(for: Self.fileProviderDomain)?.signalEnumerator(for: .workingSet)
        }
    }

    /// Thumbnails for the Files app, written once per video.
    private func writeThumbnails(for videos: [MovedVideo]) {
        for video in videos {
            guard let data = video.thumbnailJPEG else { continue }
            let url = SharedContainer.thumbnailURL(for: video.catalogID)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
