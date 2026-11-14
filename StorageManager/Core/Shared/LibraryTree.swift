import Foundation

/// The folder layout shown in the Files app: `Storage Manager › 2024 › 07 July › 2024-07-14 Beach.mov`.
/// Built from the shared snapshot; read-only.
nonisolated struct LibraryTree: Sendable {
    nonisolated enum Node: Sendable, Equatable {
        case root
        case year(Int)
        case month(year: Int, month: Int)
        case undated
        case video(LibrarySnapshot.Video, filename: String)
    }

    static let rootID = "root"

    private(set) var nodes: [String: Node] = [LibraryTree.rootID: .root]
    private(set) var parents: [String: String] = [:]
    private(set) var children: [String: [String]] = [:]

    init(snapshot: LibrarySnapshot, calendar: Calendar = .current) {
        var usedNames: [String: Set<String>] = [:]
        let videos = snapshot.videos.sorted {
            ($0.createdAt ?? .distantPast, $0.catalogID.uuidString) < ($1.createdAt ?? .distantPast, $1.catalogID.uuidString)
        }
        for video in videos {
            let folder: String
            if let date = video.createdAt {
                let parts = calendar.dateComponents([.year, .month], from: date)
                let year = parts.year ?? 0, month = parts.month ?? 0
                let yearID = Self.yearID(year)
                add(yearID, .year(year), parent: Self.rootID)
                folder = Self.monthID(year: year, month: month)
                add(folder, .month(year: year, month: month), parent: yearID)
            } else {
                folder = "undated"
                add(folder, .undated, parent: Self.rootID)
            }
            let filename = Self.uniqueName(video.displayFilename, in: &usedNames[folder, default: []])
            add(Self.videoID(video.catalogID), .video(video, filename: filename), parent: folder)
        }
        for key in Array(children.keys) {
            let sorted = (children[key] ?? []).sorted { displayName(of: $0) < displayName(of: $1) }
            children[key] = sorted
        }
    }

    static func yearID(_ year: Int) -> String { "year-\(year)" }
    static func monthID(year: Int, month: Int) -> String { String(format: "month-%04d-%02d", year, month) }
    static func videoID(_ id: UUID) -> String { "video-\(id.uuidString)" }

    func node(for id: String) -> Node? { nodes[id] }
    func parent(of id: String) -> String? { parents[id] }
    func children(of id: String) -> [String] { children[id] ?? [] }
    /// Every item except the root, for the Files "working set".
    var allIdentifiers: [String] { nodes.keys.filter { $0 != Self.rootID }.sorted() }

    func displayName(of id: String) -> String {
        switch nodes[id] {
        case .root: "Storage Manager"
        case .year(let year): String(year)
        case .month(_, let month): String(format: "%02d %@", month, Calendar(identifier: .gregorian).monthSymbols[max(0, min(11, month - 1))])
        case .undated: "Undated"
        case .video(_, let filename): filename
        case nil: id
        }
    }

    private mutating func add(_ id: String, _ node: Node, parent: String) {
        guard nodes[id] == nil else { return }
        nodes[id] = node
        parents[id] = parent
        children[parent, default: []].append(id)
    }

    /// Files requires unique names within a folder: "Beach.mov", "Beach (2).mov", …
    private static func uniqueName(_ name: String, in used: inout Set<String>) -> String {
        guard used.contains(name) else { used.insert(name); return name }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
            if !used.contains(candidate) { used.insert(candidate); return candidate }
            counter += 1
        }
    }
}
