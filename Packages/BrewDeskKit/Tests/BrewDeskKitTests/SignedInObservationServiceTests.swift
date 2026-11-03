import Foundation
import Testing
@testable import BrewDeskKit
@testable import VenueKit

/// brewdesk#249: a signed-in rating never leaves the device without a bearer
/// token. Signed-out ratings are untouched.
@Suite struct SignedInObservationServiceTests {
    private let answers = ObservationAnswers(
        laptopFriendlyToday: .yes,
        seatsAvailable: .plenty,
        outletsWorking: .plenty,
        noise: .quiet,
        wifiQuality: .fast
    )

    /// Records whether the upstream was reached; returns a decoded fixture.
    private final class Upstream: VenueObservationSubmitting, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var calls: Int { lock.withLock { count } }

        func submitObservation(venueId: String, submittedBy: String, answers: ObservationAnswers) async throws -> Venue {
            lock.withLock { count += 1 }
            return ScenarioVenueService.fixtureVenues[0]
        }
    }

    @Test func signedInWithNoTokenAsksForSignInAndNeverSubmits() async {
        let upstream = Upstream()
        let service = SignedInObservationService(
            hasSession: { true },
            accessToken: { nil },
            upstream: upstream
        )
        await #expect(throws: VenueAPIError.authenticationRequired) {
            try await service.submitObservation(venueId: "v1", submittedBy: "install-uuid", answers: answers)
        }
        #expect(upstream.calls == 0)
    }

    @Test func signedInWithTokenSubmits() async throws {
        let upstream = Upstream()
        let service = SignedInObservationService(
            hasSession: { true },
            accessToken: { "jwt" },
            upstream: upstream
        )
        _ = try await service.submitObservation(venueId: "v1", submittedBy: "install-uuid", answers: answers)
        #expect(upstream.calls == 1)
    }

    @Test func signedOutSubmitsAnonymouslyAsBefore() async throws {
        let upstream = Upstream()
        let service = SignedInObservationService(
            hasSession: { false },
            accessToken: { nil },
            upstream: upstream
        )
        _ = try await service.submitObservation(venueId: "v1", submittedBy: "install-uuid", answers: answers)
        #expect(upstream.calls == 1)
    }
}
