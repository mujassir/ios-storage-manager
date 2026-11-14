import Foundation
import SwiftData

/// A cloud account the user connected. Synced through the CloudKit private database so a new
/// iPhone knows which accounts to reconnect. Never holds tokens; those stay in the device Keychain.
///
/// CloudKit-backed SwiftData models need default values for every property and no unique constraints.
@Model
final class LinkedAccount {
    var providerRaw: String = ProviderKind.googleDrive.rawValue
    /// The provider's stable user ID (Google `sub`, Microsoft `id`). Used to make sure a reconnect
    /// signs into the same account as before.
    var providerUserID: String = ""
    var email: String = ""
    var displayName: String = ""
    var linkedAt: Date = Date.now
    var lastQuotaTotal: Int64 = 0
    var lastQuotaUsed: Int64 = 0
    var lastQuotaCheckedAt: Date?

    init(provider: ProviderKind, providerUserID: String, email: String, displayName: String) {
        self.providerRaw = provider.rawValue
        self.providerUserID = providerUserID
        self.email = email
        self.displayName = displayName
    }

    var provider: ProviderKind { ProviderKind(rawValue: providerRaw) ?? .googleDrive }

    /// Key used for the Keychain entry and in-memory provider lookup.
    var accountKey: AccountKey { AccountKey(provider: provider, providerUserID: providerUserID) }

    var lastQuotaFree: Int64 { max(0, lastQuotaTotal - lastQuotaUsed) }
}

nonisolated struct AccountKey: Hashable, Codable, Sendable, CustomStringConvertible {
    let provider: ProviderKind
    let providerUserID: String
    var description: String { "\(provider.rawValue):\(providerUserID)" }
}
