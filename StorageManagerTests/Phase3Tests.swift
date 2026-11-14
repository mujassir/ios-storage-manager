import Testing
import Foundation
@testable import StorageManager

private func video(_ name: String, date: Date?, id: UUID = UUID()) -> LibrarySnapshot.Video {
    LibrarySnapshot.Video(
        catalogID: id, title: "", originalFilename: "IMG.MOV", sizeBytes: 1_000, durationSeconds: 10,
        createdAt: date, movedAt: Date(timeIntervalSince1970: 1_700_000_000), provider: .googleDrive, providerUserID: "g1", remoteFileID: "r",
        remotePath: "Videos/x/\(name)", checksum: "c", deletedFromDevice: true
    )
}

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

struct LibraryTreeTests {
    @Test func groupsByYearAndMonth() {
        var snapshot = LibrarySnapshot.empty
        let a = video("a.mov", date: date(2024, 7, 14))
        let b = video("b.mov", date: date(2024, 8, 1))
        let c = video("c.mov", date: nil)
        snapshot.videos = [a, b, c]
        let tree = LibraryTree(snapshot: snapshot, calendar: utc)

        // "2024" sorts before "Undated".
        #expect(tree.children(of: LibraryTree.rootID) == ["year-2024", "undated"])
        #expect(tree.children(of: "year-2024") == ["month-2024-07", "month-2024-08"])
        #expect(tree.displayName(of: "month-2024-07") == "07 July")
        #expect(tree.children(of: "month-2024-07") == [LibraryTree.videoID(a.catalogID)])
        #expect(tree.parent(of: LibraryTree.videoID(c.catalogID)) == "undated")
        // undated + 2024 + two months + three videos
        #expect(tree.allIdentifiers.count == 7)
    }

    @Test func duplicateNamesGetSuffixes() {
        var snapshot = LibrarySnapshot.empty
        let first = video("Beach.mov", date: date(2024, 7, 1))
        let second = video("Beach.mov", date: date(2024, 7, 2))
        snapshot.videos = [second, first]
        let tree = LibraryTree(snapshot: snapshot, calendar: utc)
        #expect(tree.displayName(of: LibraryTree.videoID(first.catalogID)) == "Beach.mov")
        #expect(tree.displayName(of: LibraryTree.videoID(second.catalogID)) == "Beach (2).mov")
    }

    @Test func emptySnapshotHasOnlyRoot() {
        let tree = LibraryTree(snapshot: .empty)
        #expect(tree.children(of: LibraryTree.rootID).isEmpty)
        #expect(tree.allIdentifiers.isEmpty)
        #expect(tree.node(for: LibraryTree.rootID) == .root)
    }
}

struct LibrarySnapshotTests {
    @Test func roundTripsThroughDisk() throws {
        var snapshot = LibrarySnapshot.empty
        snapshot.generation = 7
        snapshot.videos = [video("a.mov", date: Date(timeIntervalSince1970: 1_700_000_000))]
        snapshot.accounts = [.init(provider: .oneDrive, providerUserID: "m1", email: "a@b.c", totalBytes: 100, usedBytes: 40, isConnected: true)]
        let url = FileManager.default.temporaryDirectory.appending(path: "snapshot-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try snapshot.save(to: url)
        let loaded = try #require(LibrarySnapshot.load(from: url))
        #expect(loaded.generation == 7)
        #expect(loaded.videos == snapshot.videos)
        #expect(loaded.cloudFreeBytes == 60)
        #expect(loaded.freedBytes == 1_000)
    }
}

struct AutoMoveRuleTests {
    private func asset(sizeMB: Int64, ageDays: Int, screen: Bool = false, favorite: Bool = false, local: Bool = true, id: String = UUID().uuidString) -> VideoAsset {
        VideoAsset(
            id: id, filename: "IMG.MOV", sizeBytes: sizeMB * 1024 * 1024, durationSeconds: 30,
            pixelWidth: 1920, pixelHeight: 1080,
            creationDate: Calendar.current.date(byAdding: .day, value: -ageDays, to: .now),
            latitude: nil, longitude: nil, isScreenRecording: screen, isFavorite: favorite, isLocallyAvailable: local
        )
    }

    @Test func sizeAgeAndTypeConditions() {
        let rule = AutoMoveRule(name: "Old screen recordings", olderThanDays: 30, onlyScreenRecordings: true)
        #expect(rule.matches(asset(sizeMB: 10, ageDays: 40, screen: true)))
        #expect(!rule.matches(asset(sizeMB: 10, ageDays: 10, screen: true)))
        #expect(!rule.matches(asset(sizeMB: 10, ageDays: 40, screen: false)))

        let large = AutoMoveRule(name: "Large", minimumSizeMB: 1024)
        #expect(large.matches(asset(sizeMB: 2048, ageDays: 1)))
        #expect(!large.matches(asset(sizeMB: 500, ageDays: 1)))
    }

    @Test func skipsFavoritesDisabledRulesAndICloudOnly() {
        var rule = AutoMoveRule(name: "Any")
        #expect(!rule.matches(asset(sizeMB: 10, ageDays: 1, favorite: true)))
        #expect(!rule.matches(asset(sizeMB: 10, ageDays: 1, local: false)))
        rule.isEnabled = false
        #expect(!rule.matches(asset(sizeMB: 10, ageDays: 1)))
    }

    @Test func planUsesFirstMatchingRuleAndSkipsVideosInCloud() {
        let account = AccountKey(provider: .oneDrive, providerUserID: "m1")
        let screen = AutoMoveRule(name: "Screen", onlyScreenRecordings: true, destination: .account(account))
        let any = AutoMoveRule(name: "Any")
        let recording = asset(sizeMB: 10, ageDays: 1, screen: true)
        let normal = asset(sizeMB: 10, ageDays: 1)
        let alreadyMoved = asset(sizeMB: 10, ageDays: 1, id: "moved")
        let plan = AutoMoveRule.plan([screen, any], videos: [recording, normal, alreadyMoved], excluding: ["moved"])
        #expect(plan[.account(account)]?.map(\.id) == [recording.id])
        #expect(plan[.automatic]?.map(\.id) == [normal.id])
    }

    @Test func rulesRoundTripAsJSON() throws {
        let rules = AutoMoveRule.presets + [AutoMoveRule(name: "To OneDrive", destination: .account(AccountKey(provider: .oneDrive, providerUserID: "x")))]
        let decoded = try JSONDecoder().decode([AutoMoveRule].self, from: JSONEncoder().encode(rules))
        #expect(decoded == rules)
    }
}

struct DeepLinkTests {
    @Test func parsesLinks() {
        #expect(DeepLink(url: URL(string: "storagemanager://cleanup")!) == .cleanup)
        #expect(DeepLink(url: URL(string: "storagemanager://videos?filter=large")!) == .videos(.large))
        #expect(DeepLink(url: URL(string: "storagemanager://videos")!) == .videos(nil))
        #expect(DeepLink(url: URL(string: "storagemanager://library")!)?.tab == .library)
        #expect(DeepLink(url: URL(string: "https://example.com")!) == nil)
        #expect(DeepLink(url: URL(string: "storagemanager://nope")!) == nil)
    }
}
