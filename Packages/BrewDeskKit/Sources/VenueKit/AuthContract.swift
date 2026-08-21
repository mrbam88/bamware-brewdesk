import Foundation

// BrewDesk accounts (brewdesk#48, Apple 1.2 UGC compliance pack).
//
// Accounts are OPTIONAL: the whole app works anonymously; an account only
// gates community submissions (future). Auth is served by bamware-auth-service
// (multi-tenant, bcrypt + JWT). BrewDesk is the `bamware-brewdesk` tenant —
// see the auth-service AGENTS.md "Tenants" section; onboarding was
// config-not-code (auth-service PR #6).

/// The one place BrewDesk's tenant identity lives. A typo here would silently
/// create a fresh, isolated tenant partition on the auth service — pinned by
/// package tests so it can never drift.
public enum BrewDeskTenant {
    public static let id = "bamware-brewdesk"
}

/// The signed-in user, as returned by the auth service. The service sends
/// more keys (role, createdAt, schemaVersion, …); we decode only what the
/// app displays so additive server changes never break the client.
public struct AuthUser: Codable, Hashable, Sendable {
    public let userId: String
    public let email: String
    public let name: String
    public let tenantId: String

    public init(userId: String, email: String, name: String, tenantId: String) {
        self.userId = userId
        self.email = email
        self.name = name
        self.tenantId = tenantId
    }
}

/// A signed-in session: the token pair plus the user it belongs to.
/// Access tokens expire in ≤15 min; v1 does not auto-refresh (account
/// actions are rare and re-login is cheap) — the refresh token is stored
/// so refresh can ship without a session-shape migration.
public struct AuthSession: Codable, Hashable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let user: AuthUser

    public init(accessToken: String, refreshToken: String, user: AuthUser) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.user = user
    }
}

public enum AuthAPIError: Error, Equatable, LocalizedError {
    /// Wrong email/password (or unknown account — the service deliberately
    /// does not distinguish, to prevent account enumeration).
    case invalidCredentials
    /// Register hit an email that already has an account in this tenant.
    case emailAlreadyRegistered
    /// The request failed validation server-side (e.g. password < 8 chars).
    case validation
    case invalidResponse
    case http(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Invalid email or password."
        case .emailAlreadyRegistered: "That email already has an account. Try signing in."
        case .validation: "Check your email and password (at least 8 characters) and try again."
        case .invalidResponse: "Unexpected response from the account service."
        case .http(let statusCode): "Account service error (HTTP \(statusCode))."
        }
    }
}

/// Seam for the auth-service client. Live: `AuthAPI`. Deterministic
/// (UI tests / previews): `AuthScenarioService`. Resolved screen-side via
/// `AccountServiceResolver` so the composition root stays untouched
/// (same pattern as `ObservationServiceResolver`).
public protocol AccountAuthServing: Sendable {
    func register(email: String, password: String, name: String) async throws -> AuthSession
    func signIn(email: String, password: String) async throws -> AuthSession
    /// Idempotent server-side (404 == already gone == success).
    func deleteAccount(accessToken: String) async throws
}

/// Step 1 of the ordered account deletion (see `AccountModel.deleteAccount`):
/// delete the user's app content BEFORE the auth record, because deleting the
/// auth record kills the very token the content deletion needs.
///
/// BrewDesk v1 stores NO server-side user content (community submissions are
/// anonymous per-install UUIDs — `ObservationSubmitterIdentity`). When
/// account-attributed submissions ship, the venue-engine content cascade
/// implements this protocol; the ordering is already pinned by
/// `AccountModelTests` so it cannot regress.
public protocol AccountContentDeleting: Sendable {
    func deleteUserContent(accessToken: String) async throws
}

/// v1: nothing to delete — documented no-op (see `AccountContentDeleting`).
public struct NoUserContentService: AccountContentDeleting {
    public init() {}
    public func deleteUserContent(accessToken: String) async throws {}
}
