import Testing
import Foundation
@testable import StorageManager

struct QuickXorHashTests {
    private func hash(_ data: Data, chunkSize: Int? = nil) -> String {
        var hasher = QuickXorHash()
        if let chunkSize {
            var offset = 0
            while offset < data.count {
                hasher.update(data.subdata(in: offset..<min(data.count, offset + chunkSize)))
                offset += chunkSize
            }
        } else {
            hasher.update(data)
        }
        return hasher.base64Digest()
    }

    @Test func emptyInput() {
        #expect(hash(Data()) == "AAAAAAAAAAAAAAAAAAAAAAAAAAA=")
    }

    @Test func singleByte() {
        #expect(hash(Data("J".utf8)) == "SgAAAAAAAAAAAAAAAQAAAAAAAAA=")
    }

    @Test func shortString() {
        #expect(hash(Data("Hello, World!".utf8)) == "SCgDG9jwBhaA4ApvnQMbyBACAAA=")
    }

    /// Vectors generated from a port of Microsoft's reference implementation; the result must not depend on chunking.
    @Test(arguments: [nil, 7, 333, 4096])
    func longInputIsChunkIndependent(chunkSize: Int?) {
        let data = Data((0..<10_000).map { UInt8($0 % 251) })
        #expect(hash(data, chunkSize: chunkSize) == "/D1lkEB7neNF2bAuWl2/g6E9skU=")
    }

    @Test func fileHasherMatchesInMemoryHash() throws {
        let data = Data((0..<(FileHasher.chunkSize + 12_345)).map { UInt8(($0 * 31) % 256) })
        let url = FileManager.default.temporaryDirectory.appending(path: "qxh-\(UUID().uuidString).bin")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try FileHasher.quickXorBase64(of: url) == hash(data))
    }

    @Test func md5OfKnownString() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "md5-\(UUID().uuidString).txt")
        try Data("The quick brown fox jumps over the lazy dog".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try FileHasher.md5Hex(of: url) == "9e107d9d372bb6826bd81d3542a419d6")
    }
}
