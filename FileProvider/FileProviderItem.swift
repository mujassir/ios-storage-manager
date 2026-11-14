import FileProvider
import UniformTypeIdentifiers

/// One file or folder in the Files app.
nonisolated final class FileProviderItem: NSObject, NSFileProviderItem, @unchecked Sendable {
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let contentType: UTType
    let capabilities: NSFileProviderItemCapabilities
    let documentSize: NSNumber?
    let childItemCount: NSNumber?
    let creationDate: Date?
    let contentModificationDate: Date?
    let itemVersion: NSFileProviderItemVersion

    private init(identifier: NSFileProviderItemIdentifier, parent: NSFileProviderItemIdentifier, filename: String,
                 contentType: UTType, capabilities: NSFileProviderItemCapabilities, size: Int64?, childCount: Int?,
                 created: Date?, modified: Date?, version: String) {
        self.itemIdentifier = identifier
        self.parentItemIdentifier = parent
        self.filename = filename
        self.contentType = contentType
        self.capabilities = capabilities
        self.documentSize = size.map { NSNumber(value: $0) }
        self.childItemCount = childCount.map { NSNumber(value: $0) }
        self.creationDate = created
        self.contentModificationDate = modified
        let data = Data(version.utf8)
        self.itemVersion = NSFileProviderItemVersion(contentVersion: data, metadataVersion: data)
    }

    static func systemIdentifier(for treeID: String) -> NSFileProviderItemIdentifier {
        treeID == LibraryTree.rootID ? .rootContainer : NSFileProviderItemIdentifier(treeID)
    }

    static func treeID(for identifier: NSFileProviderItemIdentifier) -> String {
        identifier == .rootContainer ? LibraryTree.rootID : identifier.rawValue
    }

    static func make(treeID: String, tree: LibraryTree) -> FileProviderItem? {
        guard let node = tree.node(for: treeID) else { return nil }
        let identifier = systemIdentifier(for: treeID)
        let parent = systemIdentifier(for: tree.parent(of: treeID) ?? LibraryTree.rootID)
        let name = tree.displayName(of: treeID)

        switch node {
        case .video(let video, _):
            let ext = (name as NSString).pathExtension
            return FileProviderItem(
                identifier: identifier, parent: parent, filename: name,
                contentType: UTType(filenameExtension: ext) ?? .movie,
                capabilities: [.allowsReading],
                size: video.sizeBytes, childCount: nil,
                created: video.createdAt, modified: video.createdAt ?? video.movedAt,
                version: "\(video.checksum)|\(name)"
            )
        default:
            let childCount = tree.children(of: treeID).count
            return FileProviderItem(
                identifier: identifier, parent: parent, filename: name,
                contentType: .folder,
                capabilities: [.allowsReading, .allowsContentEnumerating],
                size: nil, childCount: childCount,
                created: nil, modified: nil,
                version: "folder|\(name)|\(childCount)"
            )
        }
    }
}
