import BamwareAccounts
import Foundation
import Testing
import VenueKit

@testable import BrewDeskKit

/// Pins BrewDesk's account-platform composition (bamware-brewdesk#174, C9)
/// so a typo can never silently create a fresh, isolated tenant partition
/// on the auth service or scope the keychain wrong — same discipline the
/// pre-lift `AccountModelTests`/`AuthAPITests` pinned for the local copies
/// this ticket retired.
@Suite struct AccountCompositionTests {
    @Test func tenantIdMatchesTheRegisteredAuthServiceTenant() {
        #expect(BrewDeskAccountTenant.id == "bamware-brewdesk")
        // VenueKit.BrewDeskTenant is the single source of truth both this
        // and the community-capture upload rail read.
        #expect(BrewDeskAccountTenant.id == BrewDeskTenant.id)
    }

    @Test func keychainServiceIsBrewDeskScoped() {
        #expect(BrewDeskAccountTenant.keychainService == "io.bamware.brewdesk.auth")
    }

    @Test func configSupportsAppleAlways() {
        let config = BrewDeskAccountTenant.config(environment: .production)
        #expect(config.supportsApple)
        #expect(config.tenantId == "bamware-brewdesk")
        #expect(config.keychainService == "io.bamware.brewdesk.auth")
    }

    @Test func googleSupportFollowsWhetherAClientIDIsConfigured() {
        // No GIDClientID is configured tonight (Human-only handoff) — the
        // real accessor reads Bundle.main, which has none in the test host,
        // so this pins the absent-by-default state without needing to fake
        // Bundle.main.
        let config = BrewDeskAccountTenant.config(environment: .production)
        #expect(config.supportsGoogle == (BrewDeskAccountTenant.googleClientID != nil))
        if BrewDeskAccountTenant.googleClientID == nil {
            #expect(config.supportsGoogle == false)
            #expect(config.googleClientID == nil)
        }
    }

    // MARK: - Resolver: scenario launches get the deterministic fake

    @Test func scenarioLaunchResolvesToScenarioService() async throws {
        let environment = LaunchEnvironment(arguments: ["-UITestScenario", "fixtureOK"])
        let config = BrewDeskAccountTenant.config(environment: environment)
        let auth = AccountServiceResolver.resolve(config: config, environment: environment)
        #expect(auth is AuthScenarioService)
    }

    @Test func normalLaunchResolvesToLiveAuthAPI() {
        let auth = AccountServiceResolver.resolve(config: BrewDeskAccountTenant.config(), environment: .production)
        #expect(auth is AuthAPI)
    }

    // MARK: - Account deletion content step (bamware-brewdesk#175)

    @Test func scenarioLaunchGetsTheNoOpContentDeletionService() {
        let environment = LaunchEnvironment(arguments: ["-UITestScenario", "fixtureOK"])
        let content = AccountContentDeletionResolver.resolve(environment: environment)
        #expect(content is NoUserContentService)
    }

    @Test func normalLaunchGetsTheLiveSavedVenuesContentDeletionService() {
        let content = AccountContentDeletionResolver.resolve(environment: .production)
        #expect(content is SavedVenuesAccountContentDeleting)
    }

    @Test func scenarioLaunchGetsInMemorySessionPersistence() {
        let environment = LaunchEnvironment(arguments: ["-UITestScenario", "fixtureOK"])
        let config = BrewDeskAccountTenant.config(environment: environment)
        let persistence = AccountSessionPersistenceResolver.resolve(config: config, environment: environment)
        #expect(persistence is InMemorySessionStore)
    }

    @Test func normalLaunchGetsKeychainSessionPersistence() {
        let persistence = AccountSessionPersistenceResolver.resolve(
            config: BrewDeskAccountTenant.config(),
            environment: .production
        )
        #expect(persistence is KeychainSessionStore)
    }

    // MARK: - Scenario social auth fake — type-checks SocialSignInSupport

    @Test func scenarioSocialAuthServiceReturnsADeterministicSession() async throws {
        let service = ScenarioSocialAuthService(tenantId: "bamware-brewdesk")
        let session = try await service.socialSignIn(
            provider: .apple, idToken: "ignored", tenantId: "bamware-brewdesk", name: "Ada"
        )
        #expect(session.user.name == "Ada")
        #expect(session.user.tenantId == "bamware-brewdesk")
    }

    // MARK: - Model composition — never Google without Apple, even when a
    // client id happens to be configured, mirroring BamwareAccountUI's own
    // "never Google without Apple" enforcement at its own layer.

    @MainActor
    @Test func makeModelAlwaysOffersAppleAsAnAvailableProvider() {
        let environment = LaunchEnvironment(arguments: ["-UITestScenario", "fixtureOK"])
        let model = BrewDeskAccountStack.makeModel(environment: environment)
        #expect(model.availableProviders.contains(.apple))
    }
}
