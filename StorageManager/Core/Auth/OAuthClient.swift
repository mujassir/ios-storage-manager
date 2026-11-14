import Foundation
import CryptoKit

/// Presents the provider's sign-in page and returns the callback URL.
/// In views this wraps SwiftUI's `WebAuthenticationSession` (ASWebAuthenticationSession).
typealias WebAuthPresenter = (_ url: URL, _ callbackScheme: String) async throws -> URL

nonisolated struct OAuthConfiguration: Sendable {
    var authorizeURL: URL
    var tokenURL: URL
    var clientID: String
    var redirectURI: String
    var scopes: [String]
    var extraAuthorizeParameters: [String: String] = [:]

    var callbackScheme: String {
        URLComponents(string: redirectURI)?.scheme ?? ""
    }
}

nonisolated enum OAuthError: LocalizedError {
    case notConfigured(String)
    case missingCode
    case stateMismatch
    case providerError(String)
    case noRefreshToken

    var errorDescription: String? {
        switch self {
        case .notConfigured(let provider): "\(provider) isn't configured yet. Add its client ID to Secrets.xcconfig (see docs/SETUP.md)."
        case .missingCode: "Sign-in didn't return an authorization code."
        case .stateMismatch: "Sign-in response didn't match the request. Please try again."
        case .providerError(let message): "Sign-in failed: \(message)"
        case .noRefreshToken: "Your session expired. Please reconnect the account."
        }
    }
}

/// OAuth 2.0 authorization-code flow with PKCE for public (no client secret) iOS clients.
/// Works for both Google and Microsoft identity platforms; no third-party SDK needed.
nonisolated struct OAuthClient: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func authorize(_ config: OAuthConfiguration, loginHint: String?, presenter: WebAuthPresenter) async throws -> TokenSet {
        let verifier = Self.randomURLSafeString(byteCount: 32)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafeString(byteCount: 16)

        var components = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        if let loginHint, !loginHint.isEmpty {
            items.append(URLQueryItem(name: "login_hint", value: loginHint))
        }
        items += config.extraAuthorizeParameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = items

        let callback = try await presenter(components.url!, config.callbackScheme)
        let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = query.first(where: { $0.name == "error" })?.value {
            let description = query.first(where: { $0.name == "error_description" })?.value
            throw OAuthError.providerError(description ?? error)
        }
        guard query.first(where: { $0.name == "state" })?.value == state else { throw OAuthError.stateMismatch }
        guard let code = query.first(where: { $0.name == "code" })?.value else { throw OAuthError.missingCode }

        return try await tokenRequest(config, parameters: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientID,
            "code_verifier": verifier,
            "scope": config.scopes.joined(separator: " "),
        ], previousRefreshToken: nil)
    }

    func refresh(_ config: OAuthConfiguration, refreshToken: String) async throws -> TokenSet {
        try await tokenRequest(config, parameters: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID,
            "scope": config.scopes.joined(separator: " "),
        ], previousRefreshToken: refreshToken)
    }

    private func tokenRequest(_ config: OAuthConfiguration, parameters: [String: String], previousRefreshToken: String?) async throws -> TokenSet {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(parameters).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HTTPError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = body?["error_description"] as? String ?? body?["error"] as? String ?? "HTTP \(http.statusCode)"
            if body?["error"] as? String == "invalid_grant" { throw OAuthError.noRefreshToken }
            throw OAuthError.providerError(message)
        }
        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data).tokenSet(keepingRefreshToken: previousRefreshToken)
    }

    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func formEncode(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters.sorted { $0.key < $1.key }.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
    }
}
