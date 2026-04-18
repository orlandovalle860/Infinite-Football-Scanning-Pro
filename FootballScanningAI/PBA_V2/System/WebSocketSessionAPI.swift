//
//  WebSocketSessionAPI.swift
//  FootballScanningAI
//
//  Minimal HTTP client for the relay: create display session (POST /v1/sessions).
//

import Foundation

/// Base URL for relay HTTP API (no trailing slash).
/// Injected at build time via `INFOPLIST_KEY_RELAY_HTTP_BASE_URL` (see `Config/RelayDebug.xcconfig` and `Config/RelayRelease.xcconfig`).
enum WebSocketRelayAPIConfiguration {
    private static let infoPlistKey = "RELAY_HTTP_BASE_URL"

    static var httpBaseURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = normalizedBaseURLString(trimmed)

        guard let url = makeValidHTTPBaseURL(from: normalized) else {
            preconditionFailure(
                "RELAY_HTTP_BASE_URL must be set via xcconfig (Config/RelayDebug.xcconfig or RelayRelease.xcconfig). Got: \(trimmed.isEmpty ? "(empty)" : trimmed)"
            )
        }
        #if DEBUG
        print("[RelayWS-DEBUG] RELAY_HTTP_BASE_URL = \(url.absoluteString)")
        #endif
        return url
    }

    /// Drops trailing slashes so `URL(string:relativeTo:)` path joining behaves.
    private static func normalizedBaseURLString(_ s: String) -> String {
        var out = s
        while out.hasSuffix("/") { out.removeLast() }
        return out
    }

    private static func makeValidHTTPBaseURL(from string: String) -> URL? {
        guard !string.isEmpty, let url = URL(string: string), let scheme = url.scheme?.lowercased() else {
            return nil
        }
        guard scheme == "http" || scheme == "https", url.host != nil else { return nil }
        return url
    }
}

/// Response from `POST /v1/sessions` (relay scaffold).
struct WebSocketRelayCreateSessionResponse: Decodable {
    let sessionId: String
    let joinCode: String
    let displayToken: String
    let wsUrl: String
    let expiresAt: String?

    /// Full WebSocket URL with `sessionId`, `role=display`, and `token` query parameters.
    func webSocketURLForDisplay() throws -> URL {
        guard let base = URL(string: wsUrl) else {
            throw WebSocketSessionAPIError.invalidURL
        }
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw WebSocketSessionAPIError.invalidURL
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "sessionId", value: sessionId))
        items.append(URLQueryItem(name: "role", value: "display"))
        items.append(URLQueryItem(name: "token", value: displayToken))
        components.queryItems = items
        guard let url = components.url else {
            throw WebSocketSessionAPIError.invalidURL
        }
        return url
    }
}

/// Response from `POST /v1/sessions/join` (relay scaffold).
struct WebSocketRelayJoinSessionResponse: Decodable {
    let sessionId: String
    let coachToken: String
    let wsUrl: String
    let expiresAt: String?

    /// Full WebSocket URL with `sessionId`, `role=coach`, and `token` query parameters.
    func webSocketURLForCoach() throws -> URL {
        guard let base = URL(string: wsUrl) else {
            throw WebSocketSessionAPIError.invalidURL
        }
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw WebSocketSessionAPIError.invalidURL
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "sessionId", value: sessionId))
        items.append(URLQueryItem(name: "role", value: "coach"))
        items.append(URLQueryItem(name: "token", value: coachToken))
        components.queryItems = items
        guard let url = components.url else {
            throw WebSocketSessionAPIError.invalidURL
        }
        return url
    }
}

enum WebSocketSessionAPIError: Error {
    case invalidURL
    case httpError(statusCode: Int, body: String?)
    case decodingFailed(underlying: Error?)
}

enum WebSocketSessionAPI {
    /// Shown when HTTP join fails because the relay session or join code is no longer valid (e.g. expired).
    static let relayJoinCodeExpiredUserMessage = UserFacingErrorMessage.sessionExpiredReconnect

    /// `true` when ``joinSession(joinCode:)`` failed because the join code is invalid or the relay session expired (404 / `INVALID_JOIN_CODE`).
    static func isInvalidOrExpiredJoinSessionError(_ error: Error) -> Bool {
        guard let apiError = error as? WebSocketSessionAPIError else { return false }
        guard case .httpError(let statusCode, let body) = apiError else { return false }
        if statusCode == 404 { return true }
        return (body ?? "").lowercased().contains("invalid_join_code")
    }

    /// Creates a relay session and returns display credentials and `wsUrl`.
    static func createSession() async throws -> WebSocketRelayCreateSessionResponse {
        guard let url = URL(string: "/v1/sessions", relativeTo: WebSocketRelayAPIConfiguration.httpBaseURL)?.absoluteURL else {
            throw WebSocketSessionAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebSocketSessionAPIError.httpError(statusCode: -1, body: nil)
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw WebSocketSessionAPIError.httpError(statusCode: http.statusCode, body: body)
        }
        do {
            return try JSONDecoder().decode(WebSocketRelayCreateSessionResponse.self, from: data)
        } catch {
            throw WebSocketSessionAPIError.decodingFailed(underlying: error)
        }
    }

    /// Claims the coach slot for a session created on the display (join code from display).
    static func joinSession(joinCode: String) async throws -> WebSocketRelayJoinSessionResponse {
        guard let url = URL(string: "/v1/sessions/join", relativeTo: WebSocketRelayAPIConfiguration.httpBaseURL)?.absoluteURL else {
            throw WebSocketSessionAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let normalizedCode = joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let body: [String: String] = ["joinCode": normalizedCode]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebSocketSessionAPIError.httpError(statusCode: -1, body: nil)
        }
        guard (200...299).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8)
            throw WebSocketSessionAPIError.httpError(statusCode: http.statusCode, body: bodyStr)
        }
        do {
            return try JSONDecoder().decode(WebSocketRelayJoinSessionResponse.self, from: data)
        } catch {
            throw WebSocketSessionAPIError.decodingFailed(underlying: error)
        }
    }

    /// Safe message for coach relay HTTP join failures (and wrapped URL/network errors). Never includes status codes or response bodies.
    static func userFacingJoinErrorMessage(_ error: Error) -> String {
        if isInvalidOrExpiredJoinSessionError(error) {
            return relayJoinCodeExpiredUserMessage
        }
        if let api = error as? WebSocketSessionAPIError {
            return userFacingMessage(forAPIError: api)
        }
        return UserFacingErrorMessage.message(from: error)
    }

    private static func userFacingMessage(forAPIError error: WebSocketSessionAPIError) -> String {
        switch error {
        case .invalidURL, .decodingFailed:
            return UserFacingErrorMessage.genericRetry
        case .httpError(let statusCode, let body):
            if isInvalidOrExpiredJoinSessionError(error) {
                return relayJoinCodeExpiredUserMessage
            }
            let b = (body ?? "").uppercased()
            if statusCode == 409, b.contains("COACH_SLOT") {
                return UserFacingErrorMessage.relayJoinCodeMismatch
            }
            if statusCode == 408 || statusCode == 504 || statusCode == 429 {
                return UserFacingErrorMessage.connectionIssueRetry
            }
            if statusCode >= 500 {
                return UserFacingErrorMessage.connectionIssueRetry
            }
            if statusCode == 401 || statusCode == 403 {
                return relayJoinCodeExpiredUserMessage
            }
            if statusCode == -1 {
                return UserFacingErrorMessage.connectionIssueRetry
            }
            return UserFacingErrorMessage.genericRetry
        }
    }
}
