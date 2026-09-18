import BamwareAccounts
import BamwareAccountsGoogle
import Foundation
import VenueKit

// BrewDesk accounts (bamware-brewdesk#174, C9). Session/auth/social sign-in
// and the account screens now live in the shared `BamwareAccounts` /
// `BamwareAccountUI` packages (bamware-ios#3-#5) — this file is the app's
// own composition root for that shared platform: the one place BrewDesk's
// tenant identity, base URL, and provider wiring live. Mirrors the shape
// the pre-lift `AccountServiceResolver`/`AuthAPI.defaultBaseURL` used: same
// Debug-localhost/Release-deployed split, same `-UITestScenario`-drives-
// the-fake resolution rule as `ObservationServiceResolver`.
public enum BrewDeskAccountTenant {
    /// `VenueKit.BrewDeskTenant.id` is the single source of truth (also
    /// consumed by the community-capture upload rail) — see that type's
    /// doc comment for why it lives in VenueKit rather than here.
    public static let id = BrewDeskTenant.id
    public static let keychainService = "io.bamware.brewdesk.auth"

    /// Debug talks to a local `pnpm dev` auth service (PORT=3001 per its
    /// .env.example); Release talks to the deployed dev-stage Lambda — the
    /// only deployed instance today. Ported as-is from the pre-lift
    /// `AuthAPI.defaultBaseURL`, which `BamwareAccounts` deliberately
    /// dropped (its README: "the app always passes the URL via
    /// AccountTenantConfig").
    public static var defaultAuthBaseURL: URL {
        #if DEBUG
        URL(string: "http://localhost:3001")!
        #else
        URL(string: "https://cje3ppxv47.execute-api.us-east-1.amazonaws.com")!
        #endif
    }

    /// Info.plist `GIDClientID` — absent tonight (Human-only setup, see
    /// docs/RELEASING.md and the PR's Human-only handoff), which is exactly
    /// what makes `AccountModel.availableProviders` hide the Google button
    /// (`BamwareAccounts`' README: `supportsGoogle` gates it). Trimmed and
    /// treated as absent when empty so an unfilled Info.plist placeholder
    /// never accidentally "enables" Google with a blank client id.
    public static var googleClientID: String? {
        guard let raw = Bundle.main.infoDictionary?["GIDClientID"] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func config(environment: LaunchEnvironment = .current) -> AccountTenantConfig {
        AccountTenantConfig(
            tenantId: id,
            authBaseURL: defaultAuthBaseURL,
            keychainService: keychainService,
            supportsApple: true,
            supportsGoogle: googleClientID != nil,
            googleClientID: googleClientID
        )
    }

    /// A fresh, valid bearer token for a one-off authenticated call made
    /// outside the You tab's own `AccountModel` — today only
    /// `ServerSavedVenuePersistence` (bamware-brewdesk#175). Builds a
    /// throwaway keychain-backed `AccountSessionStore` + `SessionRefresher`
    /// on every call rather than holding one long-lived: the You tab's own
    /// `AccountModel` (`BrewDeskAccountStack.makeModel`) is a *different*
    /// `AccountSessionStore` instance, and re-reading the keychain fresh
    /// each call is the simplest way this type picks up a sign-in/out done
    /// there without the two composing a shared session object (same
    /// fresh-per-call-instance shape `LiveCaptureSubmissionService`
    /// already uses for its own default `AccountSessionStore`, just with
    /// `SessionRefresher.validAccessToken()` added on top per this
    /// ticket's explicit "uses validAccessToken()" instruction). Returns
    /// `nil` when there is no session, or when refresh itself fails —
    /// callers can't and don't need to tell those apart: either way there
    /// is no bearer token, so the caller falls back to local-only.
    public static func freshAccessToken(environment: LaunchEnvironment = .current) async -> String? {
        let sessions = AccountSessionStore(persistence: KeychainSessionStore(service: keychainService))
        guard sessions.session != nil else { return nil }
        let refresher = SessionRefresher(refreshing: AuthAPI(config: config(environment: environment)), sessions: sessions)
        return try? await refresher.validAccessToken()
    }
}

/// Same `-UITestScenario` launch-argument contract as
/// `ObservationServiceResolver`/the pre-lift `AccountServiceResolver`:
/// scenario launches get the deterministic in-process
/// `AuthScenarioService`, every normal launch gets the live `AuthAPI`.
public enum AccountServiceResolver {
    public static func resolve(
        config: AccountTenantConfig,
        environment: LaunchEnvironment = .current
    ) -> any AccountAuthServing {
        if environment.scenario != nil {
            return AuthScenarioService(tenantId: config.tenantId)
        }
        return AuthAPI(config: config)
    }
}

/// Account deletion's content step (bamware-brewdesk#175): scenario/UI-test
/// launches keep the package default `NoUserContentService()` (a no-op) so
/// AccountDeletionUITests never makes a real network call; a normal launch
/// gets the live saved-spots DELETE against venue-engine.
public enum AccountContentDeletionResolver {
    public static func resolve(environment: LaunchEnvironment = .current) -> any AccountContentDeleting {
        if environment.scenario != nil {
            return NoUserContentService()
        }
        return SavedVenuesAccountContentDeleting(syncing: SavedSpotsSyncClient())
    }
}

/// Session persistence: scenario launches get fresh-per-process in-memory
/// storage (deterministic, never leaks between UI test runs); normal
/// launches get the keychain, scoped to BrewDesk's own service name.
public enum AccountSessionPersistenceResolver {
    public static func resolve(
        config: AccountTenantConfig,
        environment: LaunchEnvironment = .current
    ) -> any AuthSessionPersisting {
        if environment.scenario != nil {
            return InMemorySessionStore()
        }
        return KeychainSessionStore(service: config.keychainService)
    }
}

/// `AuthScenarioService` (`BamwareAccounts`) does not conform to
/// `SocialAuthServing` — it only stands in for the email/password
/// `AccountAuthServing` seam. `SignInScreen`'s Apple/Google buttons are
/// still wired for UI-test/scenario launches so `AccountFlowUITests` can
/// assert on their existence at equal prominence (the ticket's acceptance
/// criterion), but the real `AppleSignInCoordinator`/`GoogleSignInCoordinator`
/// present an actual system sheet XCUITest cannot drive deterministically,
/// so no UI test taps them through to a credential exchange — this fake's
/// `socialSignIn` is therefore never actually invoked in a passing test
/// run; it exists only so `SocialSignInSupport` type-checks for scenario
/// launches. Spec-gap decision, documented in the PR description.
struct ScenarioSocialAuthService: SocialAuthServing {
    let tenantId: String

    func socialSignIn(
        provider: SocialProvider,
        idToken: String,
        tenantId: String,
        name: String?
    ) async throws -> AuthSession {
        let user = AuthUser(
            userId: "scenario-social-\(provider.rawValue)",
            email: "\(provider.rawValue)@bamware.com",
            name: name ?? "Scenario \(provider.rawValue.capitalized) User",
            tenantId: tenantId
        )
        return AuthSession(accessToken: "scenario-social-access", refreshToken: "scenario-social-refresh", user: user)
    }
}

/// Builds the whole account stack (session store, auth service, model with
/// Apple/Google wired) for a given launch — the app's one composition
/// point, called from `YouTabScreen`. Both providers are always
/// registered; `AccountModel.availableProviders` and `SignInScreen`'s
/// `SocialButtonsLayout` are what actually hide Google when
/// `googleClientID` is nil (see `BamwareAccountUI`'s README — "never
/// Google without Apple" is enforced there, not here).
@MainActor
public enum BrewDeskAccountStack {
    public static func makeModel(environment: LaunchEnvironment = .current) -> AccountModel {
        let config = BrewDeskAccountTenant.config(environment: environment)
        let auth = AccountServiceResolver.resolve(config: config, environment: environment)
        let sessions = AccountSessionStore(
            persistence: AccountSessionPersistenceResolver.resolve(config: config, environment: environment)
        )
        let content = AccountContentDeletionResolver.resolve(environment: environment)
        let model = AccountModel(auth: auth, content: content, sessions: sessions)
        let socialAuth: any SocialAuthServing = if environment.scenario != nil {
            ScenarioSocialAuthService(tenantId: config.tenantId)
        } else if let liveAuth = auth as? any SocialAuthServing {
            liveAuth
        } else {
            ScenarioSocialAuthService(tenantId: config.tenantId)
        }
        model.socialSignIn = SocialSignInSupport(
            config: config,
            coordinators: [
                .apple: AppleSignInCoordinator(),
                .google: GoogleSignInCoordinator(clientID: config.googleClientID)
            ],
            socialAuth: socialAuth
        )
        return model
    }
}
