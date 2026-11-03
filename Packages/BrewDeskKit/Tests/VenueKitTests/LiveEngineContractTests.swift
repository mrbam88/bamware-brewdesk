import Foundation
import Testing
@testable import VenueKit

/// bd#254 follow-up: decode the LIVE production engine with the app's own
/// models. Fixtures proved nothing when the engine changed shape. Needs the
/// network, so it runs only when `BREWDESK_LIVE_CONTRACT=1` reaches the test runner (pass it as
/// `TEST_RUNNER_BREWDESK_LIVE_CONTRACT=1` to xcodebuild; the nightly
/// contract job and the pre-upload smoke script set it); PR CI skips it.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BREWDESK_LIVE_CONTRACT"] == "1"))
struct LiveEngineContractTests {
    private let prod = URL(string: "https://venuekit-ashen.vercel.app")!

    @Test func liveHealthDecodesAndAdvertisesChat() async throws {
        let api = VenueAPI(baseURL: prod)
        let health = try await api.fetchHealth()
        #expect(health != nil)
        #expect(health?.features?.chat == true)
    }

    @Test func liveVenuesDecodeAroundUnionSquare() async throws {
        let api = VenueAPI(baseURL: prod)
        let result = try await api.fetchVenuesResult(VenueQuery(lat: 40.7359, lng: -73.9911, radiusM: 800, limit: 50))
        #expect(!result.venues.isEmpty)
    }
}
