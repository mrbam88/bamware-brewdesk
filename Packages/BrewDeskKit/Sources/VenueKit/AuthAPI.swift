import Foundation

/// Async client for bamware-auth-service (brewdesk#48). Same shape discipline
/// as `VenueAPI`: compile-time base URL, fail-fast session, typed errors.
///
/// Endpoint contract (auth-service `src/handlers/authHandler.ts`):
/// - `POST /auth/register` `{email, password, name, tenantId}` → 201
///   `{tokens: {accessToken, refreshToken}, user}`; 409 email taken.
/// - `POST /auth/login` `{email, password, tenantId}` → 200 same envelope;
///   401 invalid credentials.
/// - `DELETE /auth/account` (Bearer) → 200 `{ok:true}`; idempotent — a 404
///   means "already gone" and is treated as success client-side, so the
///   deletion flow is safe to re-run after a partial failure (Baat's
///   ordered-deletion pattern, dating-app #18).
public struct AuthAPI: AccountAuthServing, Sendable {
    /// Debug talks to a local `pnpm dev` auth service (PORT=3001 per its
    /// .env.example); Release talks to the deployed dev-stage Lambda — the
    /// only deployed instance today (flagged on the #48 PR: revisit when a
    /// prod stage exists).
    public static var defaultBaseURL: URL {
        #if DEBUG
        URL(string: "http://localhost:3001")!
        #else
        URL(string: "https://cje3ppxv47.execute-api.us-east-1.amazonaws.com")!
        #endif
    }

    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = AuthAPI.defaultBaseURL, session: URLSession = VenueAPI.defaultSession) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - AccountAuthServing

    public func register(email: String, password: String, name: String) async throws -> AuthSession {
        let body = RegisterBody(email: email, password: password, name: name, tenantId: BrewDeskTenant.id)
        return try await post("/auth/register", body: body) { status in
            switch status {
            case 409: AuthAPIError.emailAlreadyRegistered
            case 400: AuthAPIError.validation
            default: AuthAPIError.http(statusCode: status)
            }
        }
    }

    public func signIn(email: String, password: String) async throws -> AuthSession {
        let body = LoginBody(email: email, password: password, tenantId: BrewDeskTenant.id)
        return try await post("/auth/login", body: body) { status in
            switch status {
            case 401: AuthAPIError.invalidCredentials
            case 400: AuthAPIError.validation
            default: AuthAPIError.http(statusCode: status)
            }
        }
    }

    public func deleteAccount(accessToken: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("/auth/account"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthAPIError.invalidResponse }
        switch http.statusCode {
        case 200...299: return
        case 404: return // already gone — idempotent success
        case 401: throw AuthAPIError.invalidCredentials
        default: throw AuthAPIError.http(statusCode: http.statusCode)
        }
    }

    // MARK: - Plumbing

    private struct RegisterBody: Encodable {
        let email, password, name, tenantId: String
    }

    private struct LoginBody: Encodable {
        let email, password, tenantId: String
    }

    /// The login/register response envelope. `user` decodes the subset the
    /// app needs (see `AuthUser`).
    private struct SessionEnvelope: Decodable {
        struct Tokens: Decodable {
            let accessToken: String
            let refreshToken: String
        }
        let tokens: Tokens
        let user: AuthUser
    }

    private func post(
        _ path: String,
        body: some Encodable,
        errorForStatus: (Int) -> AuthAPIError
    ) async throws -> AuthSession {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw errorForStatus(http.statusCode) }
        do {
            let envelope = try JSONDecoder().decode(SessionEnvelope.self, from: data)
            return AuthSession(
                accessToken: envelope.tokens.accessToken,
                refreshToken: envelope.tokens.refreshToken,
                user: envelope.user
            )
        } catch {
            throw AuthAPIError.invalidResponse
        }
    }
}
