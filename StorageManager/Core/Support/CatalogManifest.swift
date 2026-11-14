import Foundation

/// `Storage Manager/index.json` inside every cloud account: a copy of the catalog entries stored there.
/// If iCloud is off or its data is gone, reconnecting the account rebuilds the gallery from this file.
nonisolated struct CatalogManifest: Codable, Sendable, Equatable {
    static let currentVersion = 1

    var version: Int = CatalogManifest.currentVersion
    var updatedAt: Date
    var entries: [Entry]

    nonisolated struct Entry: Codable, Sendable, Equatable, Identifiable {
        var catalogID: UUID
        var originalFilename: String
        var title: String
        var placeName: String
        var keywords: String
        var sizeBytes: Int64
        var durationSeconds: Double
        var pixelWidth: Int
        var pixelHeight: Int
        var createdAt: Date?
        var latitude: Double?
        var longitude: Double?
        var remoteFileID: String
        var remotePath: String
        var checksum: String
        var movedAt: Date

        var id: UUID { catalogID }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func encoded() throws -> Data { try Self.encoder.encode(self) }
    static func decode(_ data: Data) throws -> CatalogManifest { try decoder.decode(CatalogManifest.self, from: data) }

    /// Replaces entries with the same catalogID and appends new ones.
    func merging(_ newEntries: [Entry], at date: Date = .now) -> CatalogManifest {
        var byID = Dictionary(entries.map { ($0.catalogID, $0) }, uniquingKeysWith: { _, new in new })
        for entry in newEntries { byID[entry.catalogID] = entry }
        let sorted = byID.values.sorted { ($0.createdAt ?? .distantPast, $0.catalogID.uuidString) < ($1.createdAt ?? .distantPast, $1.catalogID.uuidString) }
        return CatalogManifest(version: Self.currentVersion, updatedAt: date, entries: sorted)
    }

    func removing(catalogIDs: Set<UUID>, at date: Date = .now) -> CatalogManifest {
        CatalogManifest(version: Self.currentVersion, updatedAt: date, entries: entries.filter { !catalogIDs.contains($0.catalogID) })
    }
}
