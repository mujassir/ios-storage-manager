import Foundation

/// Builds a provider for an account whose tokens are in the (shared) Keychain.
/// Used by the app and by the Files extension.
enum ProviderFactory {
    static func oauthConfiguration(for kind: ProviderKind) throws -> OAuthConfiguration {
        switch kind {
        case .googleDrive: try GoogleDriveProvider.oauthConfiguration()
        case .oneDrive: try OneDriveProvider.oauthConfiguration()
        }
    }

    static func makeProvider(for key: AccountKey, store: KeychainTokenStore = KeychainTokenStore()) throws -> CloudProvider {
        let tokens = AccessTokenSource(account: key, config: try oauthConfiguration(for: key.provider), store: store)
        let http = AuthorizedHTTPClient(tokens: tokens)
        switch key.provider {
        case .googleDrive: return GoogleDriveProvider(account: key, http: http)
        case .oneDrive: return OneDriveProvider(account: key, http: http)
        }
    }
}
