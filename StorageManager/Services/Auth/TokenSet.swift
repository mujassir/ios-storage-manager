import Foundation

nonisolated struct TokenSet: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    /// Treat tokens as expired a minute early so a request never starts with a token about to lapse.
    var isExpired: Bool { expiresAt.addingTimeInterval(-60) <= .now }
}

nonisolated struct OAuthTokenResponse: Decodable, Sendable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double?

    func tokenSet(keepingRefreshToken previous: String? = nil) -> TokenSet {
        TokenSet(
            accessToken: access_token,
            // Google omits refresh_token on refresh; Microsoft rotates it. Keep the old one if none came back.
            refreshToken: refresh_token ?? previous,
            expiresAt: Date.now.addingTimeInterval(expires_in ?? 3600)
        )
    }
}
