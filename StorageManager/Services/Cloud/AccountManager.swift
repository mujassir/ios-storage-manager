import Foundation
import SwiftData
import Observation

enum AccountError: LocalizedError {
    case wrongAccount(expected: String, actual: String)
    case notConnected(String)

    var errorDescription: String? {
        switch self {
        case .wrongAccount(let expected, let actual):
            "You signed in as \(actual), but this account is \(expected). Please sign in with \(expected)."
        case .notConnected(let name):
            "\(name) needs to be reconnected."
        }
    }
}

/// Connects, reconnects and disconnects cloud accounts, and keeps each account's manifest in sync.
///
/// The list of accounts (`LinkedAccount`) syncs through iCloud. Tokens stay in this device's Keychain.
/// An account whose tokens are missing (e.g. on a new iPhone) shows as "Reconnect".
@Observable
final class AccountManager {
    @ObservationIgnored private let store = KeychainTokenStore()
    private var providers: [AccountKey: CloudProvider] = [:]
    /// Bumped whenever tokens change so views re-read `isConnected`.
    private(set) var connectionRevision = 0
    private(set) var quotas: [AccountKey: StorageQuota] = [:]

    static func oauthConfiguration(for kind: ProviderKind) throws -> OAuthConfiguration {
        switch kind {
        case .googleDrive: try GoogleDriveProvider.oauthConfiguration()
        case .oneDrive: try OneDriveProvider.oauthConfiguration()
        }
    }

    // MARK: Lookup

    func isConnected(_ account: LinkedAccount) -> Bool {
        _ = connectionRevision
        return store.hasTokens(for: account.accountKey)
    }

    func provider(for key: AccountKey) -> CloudProvider? {
        if let cached = providers[key] { return cached }
        guard store.hasTokens(for: key), let provider = try? makeProvider(for: key) else { return nil }
        providers[key] = provider
        return provider
    }

    func requireProvider(for key: AccountKey) throws -> CloudProvider {
        guard let provider = provider(for: key) else { throw AccountError.notConnected(key.provider.displayName) }
        return provider
    }

    private func makeProvider(for key: AccountKey) throws -> CloudProvider {
        let tokens = AccessTokenSource(account: key, config: try Self.oauthConfiguration(for: key.provider), store: store)
        let http = AuthorizedHTTPClient(tokens: tokens)
        switch key.provider {
        case .googleDrive: return GoogleDriveProvider(account: key, http: http)
        case .oneDrive: return OneDriveProvider(account: key, http: http)
        }
    }

    func quota(for account: LinkedAccount) -> StorageQuota? {
        quotas[account.accountKey] ?? (account.lastQuotaTotal > 0
            ? StorageQuota(totalBytes: account.lastQuotaTotal, usedBytes: account.lastQuotaUsed) : nil)
    }

    // MARK: Connect

    /// Signs in to a provider. Pass `existing` to reconnect an account that came from iCloud;
    /// the sign-in must then be the same account, so its catalog entries keep working.
    @discardableResult
    func connect(_ kind: ProviderKind, reconnecting existing: LinkedAccount? = nil,
                 presenter: WebAuthPresenter, context: ModelContext) async throws -> LinkedAccount {
        let config = try Self.oauthConfiguration(for: kind)
        let tokens = try await OAuthClient().authorize(config, loginHint: existing?.email, presenter: presenter)

        // Find out who signed in before saving the tokens under their real account key.
        let pendingKey = AccountKey(provider: kind, providerUserID: "pending-\(UUID().uuidString)")
        try store.save(tokens, for: pendingKey)
        defer { store.delete(for: pendingKey) }
        let identity = try await makeProvider(for: pendingKey).fetchIdentity()

        if let existing, existing.providerUserID != identity.providerUserID {
            throw AccountError.wrongAccount(expected: existing.email, actual: identity.email)
        }

        let key = AccountKey(provider: kind, providerUserID: identity.providerUserID)
        try store.save(store.load(for: pendingKey) ?? tokens, for: key)
        providers[key] = nil
        connectionRevision += 1

        let account = existing ?? Self.account(for: key, in: context) ?? {
            let new = LinkedAccount(provider: kind, providerUserID: identity.providerUserID, email: identity.email, displayName: identity.displayName)
            context.insert(new)
            return new
        }()
        account.email = identity.email
        account.displayName = identity.displayName
        try context.save()

        await refreshQuota(for: account)
        // Rebuild catalog entries from the cloud copy if this device doesn't have them (iCloud off or still syncing).
        try? await importManifest(for: account, context: context)
        return account
    }

    func disconnect(_ account: LinkedAccount, context: ModelContext) throws {
        let key = account.accountKey
        store.delete(for: key)
        providers[key] = nil
        quotas[key] = nil
        connectionRevision += 1
        context.delete(account)
        try context.save()
    }

    // MARK: Quota

    func refreshQuota(for account: LinkedAccount) async {
        guard let provider = provider(for: account.accountKey), let quota = try? await provider.fetchQuota() else { return }
        quotas[account.accountKey] = quota
        account.lastQuotaTotal = quota.totalBytes
        account.lastQuotaUsed = quota.usedBytes
        account.lastQuotaCheckedAt = .now
    }

    func refreshAllQuotas(_ accounts: [LinkedAccount]) async {
        for account in accounts where isConnected(account) {
            await refreshQuota(for: account)
        }
    }

    // MARK: Manifest

    /// Adds catalog entries found in the account's `index.json` that this device doesn't have yet.
    @discardableResult
    func importManifest(for account: LinkedAccount, context: ModelContext) async throws -> Int {
        guard let manifest = try await requireProvider(for: account.accountKey).readManifest() else { return 0 }
        let existing = Set(try Self.videos(for: account.accountKey, in: context).map(\.catalogID))
        var added = 0
        for entry in manifest.entries where !existing.contains(entry.catalogID) {
            context.insert(MovedVideo(manifestEntry: entry, account: account.accountKey))
            added += 1
        }
        if added > 0 { try context.save() }
        return added
    }

    /// Merges this device's catalog entries for an account into its cloud manifest.
    func syncManifest(for key: AccountKey, removing removedIDs: Set<UUID> = [], context: ModelContext) async throws {
        let provider = try requireProvider(for: key)
        let remote = try await provider.readManifest() ?? CatalogManifest(updatedAt: .now, entries: [])
        let local = try Self.videos(for: key, in: context).map(\.manifestEntry)
        try await provider.writeManifest(remote.removing(catalogIDs: removedIDs).merging(local))
    }

    // MARK: Housekeeping

    /// iCloud can deliver the same account from two devices; keep one record per account.
    func removeDuplicateAccounts(context: ModelContext) {
        guard let accounts = try? context.fetch(FetchDescriptor<LinkedAccount>(sortBy: [SortDescriptor(\.linkedAt)])) else { return }
        var seen = Set<AccountKey>()
        for account in accounts {
            if !seen.insert(account.accountKey).inserted { context.delete(account) }
        }
        try? context.save()
    }

    static func account(for key: AccountKey, in context: ModelContext) -> LinkedAccount? {
        let raw = key.provider.rawValue
        let userID = key.providerUserID
        let descriptor = FetchDescriptor<LinkedAccount>(predicate: #Predicate { $0.providerRaw == raw && $0.providerUserID == userID })
        return try? context.fetch(descriptor).first
    }

    static func videos(for key: AccountKey, in context: ModelContext) throws -> [MovedVideo] {
        let raw = key.provider.rawValue
        let userID = key.providerUserID
        return try context.fetch(FetchDescriptor<MovedVideo>(predicate: #Predicate { $0.providerRaw == raw && $0.providerUserID == userID }))
    }
}

extension MovedVideo {
    convenience init(manifestEntry entry: CatalogManifest.Entry, account: AccountKey) {
        self.init(
            originalFilename: entry.originalFilename,
            title: entry.title,
            placeName: entry.placeName,
            keywords: entry.keywords,
            sizeBytes: entry.sizeBytes,
            durationSeconds: entry.durationSeconds,
            pixelWidth: entry.pixelWidth,
            pixelHeight: entry.pixelHeight,
            createdAt: entry.createdAt,
            location: nil,
            originalAssetIdentifier: "",
            provider: account.provider,
            providerUserID: account.providerUserID,
            remoteFileID: entry.remoteFileID,
            remotePath: entry.remotePath,
            checksum: entry.checksum,
            thumbnailJPEG: nil
        )
        catalogID = entry.catalogID
        latitude = entry.latitude
        longitude = entry.longitude
        movedAt = entry.movedAt
        deletedFromDevice = true
    }

    var manifestEntry: CatalogManifest.Entry {
        CatalogManifest.Entry(
            catalogID: catalogID, originalFilename: originalFilename, title: title, placeName: placeName,
            keywords: keywords, sizeBytes: sizeBytes, durationSeconds: durationSeconds,
            pixelWidth: pixelWidth, pixelHeight: pixelHeight, createdAt: createdAt,
            latitude: latitude, longitude: longitude, remoteFileID: remoteFileID,
            remotePath: remotePath, checksum: checksum, movedAt: movedAt
        )
    }
}
