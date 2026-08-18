import Testing
@testable import BrewDeskKit
import VenueKit

@Suite @MainActor struct VenuesModelTests {
    @Test func staleFailureCannotReplaceNewerSuccess() async throws {
        let api = ControlledVenueService()
        let model = VenuesModel(api: api)

        let firstRequest = model.request
        let firstLoad = Task { await model.load(firstRequest) }
        try await api.waitForRequest(key: "any")

        model.minWifi = "fast"
        let secondRequest = model.request
        let secondLoad = Task { await model.load(secondRequest) }
        try await api.waitForRequest(key: "fast")

        await api.succeed(key: "fast")
        await secondLoad.value
        #expect(model.phase == .loaded)

        await api.fail(key: "any")
        await firstLoad.value
        #expect(model.phase == .loaded)
    }

    @Test func cancellationRestoresIdleState() async throws {
        let api = ControlledVenueService()
        let model = VenuesModel(api: api)
        let request = model.request
        let load = Task { await model.load(request) }

        try await api.waitForRequest(key: "any")
        load.cancel()
        await load.value

        #expect(model.phase == .idle)
    }

    @Test func searchChangesOnlyAfterSubmission() {
        let model = VenuesModel(api: ControlledVenueService())

        model.searchQuery = "  espresso  "
        #expect(model.request.query == nil)

        model.submitSearch()
        #expect(model.request.query == "espresso")

        model.clearSearch()
        #expect(model.searchQuery.isEmpty)
        #expect(model.request.query == nil)
    }

    @Test func centerUpdateRestartsOnlyForNewCoordinates() {
        let model = VenuesModel(api: ControlledVenueService())

        #expect(model.updateCenterIfNeeded(lat: 40.71, lng: -74.0))
        let updatedRequest = model.request
        #expect(updatedRequest.centerLat == 40.71)
        #expect(updatedRequest.centerLng == -74.0)

        #expect(!model.updateCenterIfNeeded(lat: 40.71, lng: -74.0))
        #expect(model.request == updatedRequest)
    }
}

private actor ControlledVenueService: VenueServing {
    private enum TestError: Error { case failed, timedOut }
    private enum Outcome { case success, failure }
    private var requests: Set<String> = []
    private var outcomes: [String: Outcome] = [:]

    nonisolated var supportsSpeedTest: Bool { false }

    func fetchVenues(
        lat: Double?,
        lng: Double?,
        radiusM: Int,
        wifiMin: String?,
        outletsMin: String?,
        laptopFriendly: Bool,
        neighborhood: String?,
        query: String?,
        sort: String,
        limit: Int
    ) async throws -> [Venue] {
        let key = wifiMin ?? "any"
        requests.insert(key)
        while true {
            try Task.checkCancellation()
            if let outcome = outcomes.removeValue(forKey: key) {
                switch outcome {
                case .success: return []
                case .failure: throw TestError.failed
                }
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    func submitSpeedTest(venueId: String, mbpsDown: Double) async throws -> Venue {
        throw TestError.failed
    }

    func measureDownloadMbps(samples: Int) async throws -> Double {
        throw TestError.failed
    }

    func waitForRequest(key: String) async throws {
        for _ in 0..<1_000 {
            if requests.contains(key) { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw TestError.timedOut
    }

    func succeed(key: String) {
        outcomes[key] = .success
    }

    func fail(key: String) {
        outcomes[key] = .failure
    }
}
