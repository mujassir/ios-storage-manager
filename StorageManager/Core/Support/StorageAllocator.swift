import Foundation

/// Picks which connected account each video goes to. Prefers the account with the most free space,
/// keeps a safety margin, and remembers space already reserved by earlier files in the same batch.
nonisolated struct StorageAllocator: Sendable {
    /// Space left free in every account so a provider never hits 100% full.
    static let defaultHeadroom: Int64 = 100 * 1024 * 1024

    private(set) var freeBytes: [AccountKey: Int64]
    let headroom: Int64

    init(freeBytes: [AccountKey: Int64], headroom: Int64 = StorageAllocator.defaultHeadroom) {
        self.freeBytes = freeBytes
        self.headroom = headroom
    }

    /// Returns the account to use, or nil if none fits. Reserves the space when successful.
    /// - Parameter preferred: a specific account the user chose; nil means automatic.
    mutating func allocate(sizeBytes: Int64, preferred: AccountKey? = nil) -> AccountKey? {
        let candidate: AccountKey?
        if let preferred {
            candidate = fits(sizeBytes, in: preferred) ? preferred : nil
        } else {
            candidate = freeBytes
                .filter { fits(sizeBytes, in: $0.key) }
                .max { lhs, rhs in
                    lhs.value == rhs.value ? lhs.key.description > rhs.key.description : lhs.value < rhs.value
                }?
                .key
        }
        if let candidate { freeBytes[candidate, default: 0] -= sizeBytes }
        return candidate
    }

    /// Gives space back, e.g. when an upload failed.
    mutating func release(sizeBytes: Int64, from account: AccountKey) {
        freeBytes[account, default: 0] += sizeBytes
    }

    func fits(_ sizeBytes: Int64, in account: AccountKey) -> Bool {
        (freeBytes[account] ?? 0) - headroom >= sizeBytes
    }

    var totalFreeBytes: Int64 { freeBytes.values.reduce(0) { $0 + max(0, $1 - headroom) } }
}
