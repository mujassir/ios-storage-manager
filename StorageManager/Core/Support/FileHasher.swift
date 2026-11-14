import Foundation
import CryptoKit

/// Streams a file from disk and computes the checksum a provider will report, so the upload can be verified.
/// Synchronous and nonisolated: call it from `Task.detached` so large videos never block the UI.
nonisolated enum FileHasher {
    static let chunkSize = 4 * 1024 * 1024

    static func checksum(of url: URL, kind: ChecksumKind) throws -> String {
        switch kind {
        case .md5Hex: try md5Hex(of: url)
        case .quickXorBase64: try quickXorBase64(of: url)
        }
    }

    static func md5Hex(of url: URL) throws -> String {
        var hasher = Insecure.MD5()
        try forEachChunk(of: url) { hasher.update(data: $0) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func quickXorBase64(of url: URL) throws -> String {
        var hasher = QuickXorHash()
        try forEachChunk(of: url) { hasher.update($0) }
        return hasher.base64Digest()
    }

    static func forEachChunk(of url: URL, _ body: (Data) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while true {
            try Task.checkCancellation()
            let chunk = try autoreleasepool { try handle.read(upToCount: chunkSize) } ?? Data()
            if chunk.isEmpty { break }
            try body(chunk)
        }
    }

    /// Reads one slice of a file. Used by chunked uploads.
    static func readChunk(of url: URL, offset: Int64, length: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        return try handle.read(upToCount: length) ?? Data()
    }

    static func fileSize(of url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}

#if !canImport(ObjectiveC)
// Linux test builds have no autoreleasepool.
nonisolated func autoreleasepool<T>(invoking body: () throws -> T) rethrows -> T { try body() }
#endif
