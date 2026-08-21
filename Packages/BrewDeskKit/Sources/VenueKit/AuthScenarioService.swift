import Foundation

/// Deterministic stand-in for `AuthAPI`, mirroring `ScenarioVenueService`'s
/// role for the venue engine: no network, no persistence, fresh per process.
/// The app resolves it (via `AccountServiceResolver`) whenever it is launched
/// with `-UITestScenario <name>` — account flows are orthogonal to the venue
/// scenarios, so every scenario shares this one in-memory auth world.
///
/// Seeded account (mirrors auth-service `src/scripts/seed.ts` style):
/// `tester@bamware.com` / `BrewDesk1!` ("Test Taster"). Registered accounts
/// live for the process lifetime via `shared`, so sign-out → sign-in-again
/// works across screen instances within one UI test launch.
public actor AuthScenarioService: AccountAuthServing {
    public static let seededEmail = "tester@bamware.com"
    public static let seededPassword = "BrewDesk1!"
    public static let seededName = "Test Taster"

    /// Process-wide instance for scenario launches (fresh per app launch —
    /// each UI test starts a new process). Package tests construct their own.
    public static let shared = AuthScenarioService()

    private struct Account {
        let user: AuthUser
        let password: String
    }

    private var accountsByEmail: [String: Account] = [:]
    private var emailByAccessToken: [String: String] = [:]
    private var counter = 0

    public init(seeded: Bool = true) {
        if seeded {
            let user = AuthUser(
                userId: "scenario-user-seeded",
                email: Self.seededEmail,
                name: Self.seededName,
                tenantId: BrewDeskTenant.id
            )
            accountsByEmail[Self.seededEmail] = Account(user: user, password: Self.seededPassword)
        }
    }

    public func register(email: String, password: String, name: String) async throws -> AuthSession {
        let key = normalize(email)
        guard accountsByEmail[key] == nil else { throw AuthAPIError.emailAlreadyRegistered }
        guard password.count >= 8 else { throw AuthAPIError.validation }
        counter += 1
        let user = AuthUser(
            userId: "scenario-user-\(counter)",
            email: key,
            name: name,
            tenantId: BrewDeskTenant.id
        )
        accountsByEmail[key] = Account(user: user, password: password)
        return session(for: user)
    }

    public func signIn(email: String, password: String) async throws -> AuthSession {
        let key = normalize(email)
        guard let account = accountsByEmail[key], account.password == password else {
            throw AuthAPIError.invalidCredentials
        }
        return session(for: account.user)
    }

    public func deleteAccount(accessToken: String) async throws {
        // Idempotent, like the real endpoint: unknown token → already gone.
        guard let email = emailByAccessToken.removeValue(forKey: accessToken) else { return }
        accountsByEmail.removeValue(forKey: email)
    }

    // MARK: - Helpers

    private func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func session(for user: AuthUser) -> AuthSession {
        let token = "scenario-access-\(user.userId)-\(counter)"
        emailByAccessToken[token] = user.email
        return AuthSession(accessToken: token, refreshToken: "scenario-refresh-\(user.userId)", user: user)
    }
}
