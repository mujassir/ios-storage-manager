import Foundation

nonisolated enum HTTPError: LocalizedError {
    case invalidResponse
    case status(Int, String)

    var statusCode: Int? {
        if case .status(let code, _) = self { return code }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The server sent an unexpected response."
        case .status(let code, let message): "Server error \(code): \(message)"
        }
    }

    /// Errors worth retrying: rate limits and server-side failures.
    var isTransient: Bool {
        guard let code = statusCode else { return true }
        return code == 408 || code == 429 || (500..<600).contains(code)
    }
}

/// Network rules from Settings, read on every request.
nonisolated enum NetworkPolicy {
    static let wifiOnlyKey = "settings.wifiOnly"

    static var allowsCellular: Bool {
        // Wi-Fi only is the default, so a missing value means "no cellular".
        let defaults = SharedContainer.defaults
        return defaults.object(forKey: wifiOnlyKey) == nil ? false : !defaults.bool(forKey: wifiOnlyKey)
    }
}

/// Authenticated JSON/HTTP helper shared by the cloud providers. Adds the bearer token and
/// retries once with a fresh token on 401.
final class AuthorizedHTTPClient {
    let tokens: AccessTokenSource
    let session: URLSession

    init(tokens: AccessTokenSource, session: URLSession = .shared) {
        self.tokens = tokens
        self.session = session
    }

    func data(for request: URLRequest, authorized: Bool = true, acceptedStatus: Set<Int> = []) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            var request = request
            request.allowsCellularAccess = NetworkPolicy.allowsCellular
            if authorized {
                let token = try await tokens.validAccessToken(forceRefresh: attempt > 0)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw HTTPError.invalidResponse }
            if http.statusCode == 401 && authorized && attempt == 0 {
                attempt += 1
                continue
            }
            guard (200..<300).contains(http.statusCode) || acceptedStatus.contains(http.statusCode) else {
                throw HTTPError.status(http.statusCode, Self.errorMessage(from: data))
            }
            return (data, http)
        }
    }

    func json<T: Decodable>(_ type: T.Type, for request: URLRequest) async throws -> T {
        let (data, _) = try await data(for: request)
        return try JSONDecoder.api.decode(T.self, from: data)
    }

    /// Downloads to a file the caller owns.
    func download(_ request: URLRequest, to destination: URL, authorized: Bool = true) async throws {
        var request = request
        request.allowsCellularAccess = NetworkPolicy.allowsCellular
        if authorized {
            request.setValue("Bearer \(try await tokens.validAccessToken())", forHTTPHeaderField: "Authorization")
        }
        let (tempURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse else { throw HTTPError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPError.status(http.statusCode, "Download failed")
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    static func errorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
            if let message = object["error_description"] as? String { return message }
            if let message = object["error"] as? String { return message }
        }
        return String(data: data.prefix(300), encoding: .utf8) ?? "Unknown error"
    }
}

/// Retries an operation with exponential backoff on network and transient server errors.
func withRetry<T>(attempts: Int = 4, initialDelay: Duration = .seconds(1), _ operation: () async throws -> T) async throws -> T {
    var delay = initialDelay
    var lastError: Error?
    for attempt in 1...attempts {
        do {
            return try await operation()
        } catch {
            lastError = error
            let retryable = (error as? HTTPError)?.isTransient ?? (error is URLError)
            guard retryable, attempt < attempts, !Task.isCancelled else { throw error }
            try await Task.sleep(for: delay)
            delay *= 2
        }
    }
    throw lastError ?? HTTPError.invalidResponse
}

extension JSONDecoder {
    nonisolated static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension URLRequest {
    nonisolated init(url: URL, method: String, json: Any? = nil) {
        self.init(url: url)
        httpMethod = method
        if let json {
            httpBody = try? JSONSerialization.data(withJSONObject: json)
            setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        }
    }
}
