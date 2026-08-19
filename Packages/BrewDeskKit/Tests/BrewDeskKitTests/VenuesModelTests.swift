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

        model.minWifi = .fast
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
        #expect(model.request.query.search == nil)

        model.submitSearch()
        #expect(model.request.query.search == "espresso")

        model.clearSearch()
        #expect(model.searchQuery.isEmpty)
        #expect(model.request.query.search == nil)
    }

    @Test func centerUpdateRestartsOnlyForNewCoordinates() {
        let model = VenuesModel(api: ControlledVenueService())

        #expect(model.updateCenterIfNeeded(lat: 40.71, lng: -74.0))
        let updatedRequest = model.request
        #expect(updatedRequest.query.lat == 40.71)
        #expect(updatedRequest.query.lng == -74.0)

        #expect(!model.updateCenterIfNeeded(lat: 40.71, lng: -74.0))
        #expect(model.request == updatedRequest)
    }

    @Test func filterCyclesAreTypedAndDeterministic() {
        let model = VenuesModel(api: ControlledVenueService())

        model.cycleWifiMinimum()
        #expect(model.minWifi == .ok)
        model.cycleWifiMinimum()
        #expect(model.minWifi == .fast)
        model.cycleWifiMinimum()
        #expect(model.minWifi == nil)

        model.cycleOutletMinimum()
        #expect(model.minOutlets == .some)
        model.cycleOutletMinimum()
        #expect(model.minOutlets == .plenty)
        model.cycleOutletMinimum()
        #expect(model.minOutlets == nil)
    }
}

private actor ControlledVenueService: VenueListing {
    private enum TestError: Error { case failed, timedOut }
    private enum Outcome { case success, failure }
    private var requests: Set<String> = []
    private var outcomes: [String: Outcome] = [:]

    func fetchVenues(_ query: VenueQuery) async throws -> [Venue] {
        let key = query.wifiMinimum?.rawValue ?? "any"
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
