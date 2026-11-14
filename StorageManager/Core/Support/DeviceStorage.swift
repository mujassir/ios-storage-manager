import Foundation

/// Free and total space on the phone.
nonisolated struct DeviceStorage: Equatable, Codable, Sendable {
    var totalBytes: Int64
    var availableBytes: Int64
    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }

    static func current() -> DeviceStorage {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return DeviceStorage(
            totalBytes: Int64(values?.volumeTotalCapacity ?? 0),
            availableBytes: values?.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }
}
