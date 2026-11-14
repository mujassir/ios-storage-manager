import FileProvider

/// Lists a folder (or, for the working set, everything). Changes are reported by expiring the sync anchor
/// whenever the app writes a new snapshot, so the system re-reads the (small) catalog.
nonisolated final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator, @unchecked Sendable {
    /// nil means the working set.
    private let containerID: String?

    init(containerID: String?) {
        self.containerID = containerID
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        let tree = LibraryTree(snapshot: LibrarySnapshot.load() ?? .empty)
        let ids = containerID.map { tree.children(of: $0) } ?? tree.allIdentifiers
        observer.didEnumerate(ids.compactMap { FileProviderItem.make(treeID: $0, tree: tree) })
        observer.finishEnumerating(upTo: nil)
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        let current = Self.currentAnchor()
        if anchor == current {
            observer.finishEnumeratingChanges(upTo: current, moreComing: false)
        } else {
            observer.finishEnumeratingWithError(NSFileProviderError(.syncAnchorExpired))
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(Self.currentAnchor())
    }

    static func currentAnchor() -> NSFileProviderSyncAnchor {
        let generation = LibrarySnapshot.load()?.generation ?? 0
        return NSFileProviderSyncAnchor(Data(String(generation).utf8))
    }
}
