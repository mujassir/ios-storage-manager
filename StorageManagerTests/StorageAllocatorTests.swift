import Testing
@testable import StorageManager

struct StorageAllocatorTests {
    private let drive = AccountKey(provider: .googleDrive, providerUserID: "g1")
    private let oneDrive = AccountKey(provider: .oneDrive, providerUserID: "m1")
    private let gb: Int64 = 1024 * 1024 * 1024

    @Test func picksAccountWithMostFreeSpace() {
        var allocator = StorageAllocator(freeBytes: [drive: 10 * gb, oneDrive: 4 * gb], headroom: 0)
        #expect(allocator.allocate(sizeBytes: 1 * gb) == drive)
    }

    @Test func reservesSpaceAcrossBatch() {
        var allocator = StorageAllocator(freeBytes: [drive: 5 * gb, oneDrive: 4 * gb], headroom: 0)
        #expect(allocator.allocate(sizeBytes: 3 * gb) == drive)   // drive 2 GB left
        #expect(allocator.allocate(sizeBytes: 3 * gb) == oneDrive) // oneDrive 1 GB left
        #expect(allocator.allocate(sizeBytes: 3 * gb) == nil)
    }

    @Test func respectsHeadroom() {
        var allocator = StorageAllocator(freeBytes: [drive: 1 * gb], headroom: 200 * 1024 * 1024)
        #expect(allocator.allocate(sizeBytes: 900 * 1024 * 1024) == nil)
        #expect(allocator.allocate(sizeBytes: 800 * 1024 * 1024) == drive)
    }

    @Test func preferredAccountIsUsedOrNothing() {
        var allocator = StorageAllocator(freeBytes: [drive: 10 * gb, oneDrive: 1 * gb], headroom: 0)
        #expect(allocator.allocate(sizeBytes: 512 * 1024 * 1024, preferred: oneDrive) == oneDrive)
        #expect(allocator.allocate(sizeBytes: 1 * gb, preferred: oneDrive) == nil)
    }

    @Test func releaseGivesSpaceBack() {
        var allocator = StorageAllocator(freeBytes: [drive: 2 * gb], headroom: 0)
        #expect(allocator.allocate(sizeBytes: 2 * gb) == drive)
        allocator.release(sizeBytes: 2 * gb, from: drive)
        #expect(allocator.allocate(sizeBytes: 2 * gb) == drive)
    }
}
