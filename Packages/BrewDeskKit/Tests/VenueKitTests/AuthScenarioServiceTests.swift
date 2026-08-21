import Foundation
import Testing
@testable import VenueKit

/// The deterministic auth world UI tests lean on (brewdesk#48).
@Suite struct AuthScenarioServiceTests {
    @Test func seededAccountSignsIn() async throws {
        let service = AuthScenarioService()
        let session = try await service.signIn(
            email: AuthScenarioService.seededEmail,
            password: AuthScenarioService.seededPassword
        )
        #expect(session.user.name == AuthScenarioService.seededName)
        #expect(session.user.tenantId == BrewDeskTenant.id)
        #expect(!session.accessToken.isEmpty)
    }

    @Test func wrongPasswordThrowsInvalidCredentials() async {
        let service = AuthScenarioService()
        await #expect(throws: AuthAPIError.invalidCredentials) {
            _ = try await service.signIn(
                email: AuthScenarioService.seededEmail, password: "WrongPass99!"
            )
        }
    }

    @Test func registerThenSignInRoundTrips() async throws {
        let service = AuthScenarioService()
        let registered = try await service.register(
            email: "New@Bamware.com", password: "FlatWhite11!", name: "New Taster"
        )
        #expect(registered.user.email == "new@bamware.com") // normalized

        let signedIn = try await service.signIn(email: "new@bamware.com", password: "FlatWhite11!")
        #expect(signedIn.user.userId == registered.user.userId)
    }

    @Test func registerDuplicateEmailThrows() async throws {
        let service = AuthScenarioService()
        await #expect(throws: AuthAPIError.emailAlreadyRegistered) {
            _ = try await service.register(
                email: AuthScenarioService.seededEmail, password: "FlatWhite11!", name: "Dup"
            )
        }
    }

    @Test func shortPasswordThrowsValidation() async {
        let service = AuthScenarioService()
        await #expect(throws: AuthAPIError.validation) {
            _ = try await service.register(email: "short@bamware.com", password: "short", name: "S")
        }
    }

    @Test func deleteAccountRemovesAccountAndIsIdempotent() async throws {
        let service = AuthScenarioService()
        let session = try await service.signIn(
            email: AuthScenarioService.seededEmail,
            password: AuthScenarioService.seededPassword
        )

        try await service.deleteAccount(accessToken: session.accessToken)
        await #expect(throws: AuthAPIError.invalidCredentials) {
            _ = try await service.signIn(
                email: AuthScenarioService.seededEmail,
                password: AuthScenarioService.seededPassword
            )
        }
        // Idempotent, like the real endpoint.
        try await service.deleteAccount(accessToken: session.accessToken)
        try await service.deleteAccount(accessToken: "never-issued")
    }
}
