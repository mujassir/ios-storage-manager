import Foundation

/// Hands out a valid access token for one account, refreshing it (and saving the new tokens) when needed.
/// Concurrent callers share a single in-flight refresh.
final class AccessTokenSource {
    let account: AccountKey
    private let config: OAuthConfiguration
    private let store: KeychainTokenStore
    private let oauth: OAuthClient
    private var refreshTask: Task<TokenSet, Error>?

    init(account: AccountKey, config: OAuthConfiguration, store: KeychainTokenStore, oauth: OAuthClient = OAuthClient()) {
        self.account = account
        self.config = config
        self.store = store
        self.oauth = oauth
    }

    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let tokens = store.load(for: account) else { throw OAuthError.noRefreshToken }
        if !forceRefresh && !tokens.isExpired { return tokens.accessToken }
        return try await refreshed(from: tokens).accessToken
    }

    private func refreshed(from tokens: TokenSet) async throws -> TokenSet {
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken = tokens.refreshToken else { throw OAuthError.noRefreshToken }
        let task = Task { [oauth, config] in try await oauth.refresh(config, refreshToken: refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        let newTokens = try await task.value
        try store.save(newTokens, for: account)
        return newTokens
    }
}
