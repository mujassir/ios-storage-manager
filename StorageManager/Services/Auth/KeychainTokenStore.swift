import Foundation
import Security

/// Stores OAuth tokens in the Keychain on this device only.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` means the tokens are never synced to iCloud Keychain,
/// never included in backups, and never migrate to a new iPhone. A lost phone takes its tokens with it;
/// on a new phone the user reconnects each account once. "After first unlock" lets background
/// transfers keep working while the phone is locked.
nonisolated struct KeychainTokenStore: Sendable {
    let service: String

    init(service: String = "\(AppConfig.bundleID).oauth") {
        self.service = service
    }

    func save(_ tokens: TokenSet, for account: AccountKey) throws {
        let data = try JSONEncoder().encode(tokens)
        var query = baseQuery(for: account)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func load(for account: AccountKey) -> TokenSet? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(TokenSet.self, from: data)
    }

    func hasTokens(for account: AccountKey) -> Bool { load(for: account) != nil }

    func delete(for account: AccountKey) {
        SecItemDelete(baseQuery(for: account) as CFDictionary)
    }

    private func baseQuery(for account: AccountKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.description,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}

nonisolated enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status): "Keychain error \(status)."
        }
    }
}
