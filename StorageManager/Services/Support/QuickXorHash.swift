import Foundation

/// Microsoft's QuickXorHash, the checksum OneDrive reports for every file (`file.hashes.quickXorHash`).
/// Port of the reference implementation:
/// https://learn.microsoft.com/onedrive/developer/code-snippets/quickxorhash
nonisolated struct QuickXorHash: Sendable {
    private static let widthInBits = 160
    private static let shift = 11
    private static let bitsInLastCell = 32

    private var cells: [UInt64] = [0, 0, 0]
    private var lengthSoFar: Int64 = 0
    private var shiftSoFar = 0

    init() {}

    mutating func update(_ data: Data) {
        data.withUnsafeBytes { raw in
            update(raw.bindMemory(to: UInt8.self))
        }
    }

    mutating func update(_ bytes: UnsafeBufferPointer<UInt8>) {
        let count = bytes.count
        guard count > 0 else { return }
        let width = Self.widthInBits
        var vectorArrayIndex = shiftSoFar / 64
        var vectorOffset = shiftSoFar % 64
        let iterations = min(count, width)

        for i in 0..<iterations {
            let isLastCell = vectorArrayIndex == cells.count - 1
            let bitsInVectorCell = isLastCell ? Self.bitsInLastCell : 64

            if vectorOffset <= bitsInVectorCell - 8 {
                var j = i
                while j < count {
                    cells[vectorArrayIndex] ^= UInt64(bytes[j]) << UInt64(vectorOffset)
                    j += width
                }
            } else {
                let index1 = vectorArrayIndex
                let index2 = isLastCell ? 0 : vectorArrayIndex + 1
                let low = bitsInVectorCell - vectorOffset
                var xoredByte: UInt8 = 0
                var j = i
                while j < count {
                    xoredByte ^= bytes[j]
                    j += width
                }
                cells[index1] ^= UInt64(xoredByte) << UInt64(vectorOffset)
                cells[index2] ^= UInt64(xoredByte) >> UInt64(low)
            }

            vectorOffset += Self.shift
            while vectorOffset >= bitsInVectorCell {
                vectorArrayIndex = isLastCell ? 0 : vectorArrayIndex + 1
                vectorOffset -= bitsInVectorCell
            }
        }

        shiftSoFar = (shiftSoFar + Self.shift * (count % width)) % width
        lengthSoFar += Int64(count)
    }

    func finalize() -> Data {
        var result = [UInt8](repeating: 0, count: (Self.widthInBits - 1) / 8 + 1) // 20 bytes
        for (index, cell) in cells.enumerated() {
            let bytesToCopy = index < cells.count - 1 ? 8 : result.count - index * 8
            for b in 0..<bytesToCopy {
                result[index * 8 + b] = UInt8(truncatingIfNeeded: cell >> UInt64(b * 8))
            }
        }
        // XOR the little-endian file length into the last 8 bytes.
        let offset = Self.widthInBits / 8 - 8
        for b in 0..<8 {
            result[offset + b] ^= UInt8(truncatingIfNeeded: UInt64(bitPattern: lengthSoFar) >> UInt64(b * 8))
        }
        return Data(result)
    }

    func base64Digest() -> String { finalize().base64EncodedString() }
}
