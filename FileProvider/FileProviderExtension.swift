import FileProvider
import Foundation

/// Shows moved videos in the Files app under "Storage Manager". Read-only; a video downloads from its
/// cloud only when opened, using the tokens shared through the Keychain access group.
nonisolated final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension, NSFileProviderThumbnailing, @unchecked Sendable {
    private let domain: NSFileProviderDomain

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
    }

    func invalidate() {}

    private func currentTree() -> LibraryTree {
        LibraryTree(snapshot: LibrarySnapshot.load() ?? .empty)
    }

    // MARK: Items

    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        let treeID = FileProviderItem.treeID(for: identifier)
        if let item = FileProviderItem.make(treeID: treeID, tree: currentTree()) {
            completionHandler(item, nil)
        } else {
            completionHandler(nil, NSFileProviderError(.noSuchItem))
        }
        return Progress()
    }

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        switch containerItemIdentifier {
        case .workingSet:
            return FileProviderEnumerator(containerID: nil)
        case .trashContainer:
            throw NSFileProviderError(.noSuchItem)
        default:
            let treeID = FileProviderItem.treeID(for: containerItemIdentifier)
            guard currentTree().node(for: treeID) != nil else { throw NSFileProviderError(.noSuchItem) }
            return FileProviderEnumerator(containerID: treeID)
        }
    }

    // MARK: Contents

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 100)
        let tree = currentTree()
        let treeID = FileProviderItem.treeID(for: itemIdentifier)
        guard case .video(let video, _)? = tree.node(for: treeID),
              let item = FileProviderItem.make(treeID: treeID, tree: tree) else {
            completionHandler(nil, nil, NSFileProviderError(.noSuchItem))
            return progress
        }

        let handler = UncheckedSendableBox(completionHandler)
        let directory = (try? NSFileProviderManager(for: domain)?.temporaryDirectoryURL()) ?? FileManager.default.temporaryDirectory
        let destination = directory.appending(path: UUID().uuidString)
        let task = Task { @MainActor in
            do {
                guard KeychainTokenStore().hasTokens(for: video.accountKey) else { throw NSFileProviderError(.notAuthenticated) }
                let provider = try ProviderFactory.makeProvider(for: video.accountKey)
                try await provider.download(video.remoteFile, to: destination)
                progress.completedUnitCount = 100
                handler.value(destination, item, nil)
            } catch {
                handler.value(nil, nil, Self.fileProviderError(for: error))
            }
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    static func fileProviderError(for error: Error) -> Error {
        if error is NSFileProviderError { return error }
        if case OAuthError.noRefreshToken = error { return NSFileProviderError(.notAuthenticated) }
        if error is URLError { return NSFileProviderError(.serverUnreachable) }
        if error is CancellationError { return CocoaError(.userCancelled) }
        return CocoaError(.fileReadUnknown)
    }

    // MARK: Read-only

    private static var readOnlyError: Error { CocoaError(.featureUnsupported) }

    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?,
                    options: NSFileProviderCreateItemOptions, request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        completionHandler(nil, [], false, Self.readOnlyError)
        return Progress()
    }

    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields,
                    contents newContents: URL?, options: NSFileProviderModifyItemOptions, request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        completionHandler(nil, [], false, Self.readOnlyError)
        return Progress()
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions, request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {
        completionHandler(Self.readOnlyError)
        return Progress()
    }

    // MARK: Thumbnails

    func fetchThumbnails(for itemIdentifiers: [NSFileProviderItemIdentifier], requestedSize size: CGSize,
                         perThumbnailCompletionHandler: @escaping (NSFileProviderItemIdentifier, Data?, Error?) -> Void,
                         completionHandler: @escaping (Error?) -> Void) -> Progress {
        let tree = currentTree()
        for identifier in itemIdentifiers {
            if case .video(let video, _)? = tree.node(for: FileProviderItem.treeID(for: identifier)) {
                perThumbnailCompletionHandler(identifier, try? Data(contentsOf: SharedContainer.thumbnailURL(for: video.catalogID)), nil)
            } else {
                perThumbnailCompletionHandler(identifier, nil, nil)
            }
        }
        completionHandler(nil)
        return Progress(totalUnitCount: Int64(itemIdentifiers.count))
    }
}
