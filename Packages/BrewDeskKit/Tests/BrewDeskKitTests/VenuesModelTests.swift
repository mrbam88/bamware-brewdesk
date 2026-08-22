import Foundation
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

        model.updateCenterIfNeeded(lat: 40.71, lng: -74.0)
        let secondRequest = model.request
        let secondLoad = Task { await model.load(secondRequest) }
        try await api.waitForRequest(key: "moved")

        await api.succeed(key: "moved")
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

    // MARK: - Cold start (brewdesk#28)

    @Test func snapshotPaintsBeforeTheFirstAnswerAndYieldsToLiveData() async throws {
        let api = ControlledVenueService()
        let model = VenuesModel(api: api, snapshot: ScenarioVenueService.fixtureVenues)
        let request = model.request
        let load = Task { await model.load(request) }
        try await api.waitForRequest(key: "any")

        #expect(model.phase == .loading)
        #expect(model.venues.count == 3)
        #expect(model.isShowingSnapshot)
        #expect(model.snapshotBanner == .loading)

        await api.succeed(key: "any")
        await load.value
        #expect(model.phase == .loaded)
        #expect(model.venues.isEmpty)          // the engine's answer wins, even when empty
        #expect(!model.isShowingSnapshot)
        #expect(model.snapshotBanner == nil)
    }

    @Test func snapshotSurvivesFailureAsOfflineBanner() async {
        let model = VenuesModel(api: ScenarioVenueService(scenario: .offline),
                                snapshot: ScenarioVenueService.fixtureVenues)
        await model.load(model.request)

        guard case .failed = model.phase else {
            Issue.record("expected .failed, got \(model.phase)"); return
        }
        #expect(model.venues.count == 3)
        #expect(model.isShowingSnapshot)
        #expect(model.snapshotBanner == .offline)
    }

    @Test func snapshotIsNeverReseededAfterALiveAnswer() async throws {
        let api = ControlledVenueService()
        let model = VenuesModel(api: api, snapshot: ScenarioVenueService.fixtureVenues)

        let first = Task { await model.load(model.request) }
        try await api.waitForRequest(key: "any")
        await api.succeed(key: "any")
        await first.value
        #expect(model.venues.isEmpty)

        model.updateCenterIfNeeded(lat: 40.71, lng: -74.0)
        let second = Task { await model.load(model.request) }
        try await api.waitForRequest(key: "moved")
        #expect(model.venues.isEmpty)          // empty stays empty — no snapshot flash
        #expect(model.snapshotBanner == nil)
        await api.fail(key: "moved")
        await second.value
        #expect(model.snapshotBanner == nil)
    }

    @Test func retryAfterOfflineRecoversWithoutANewModel() async {
        let model = VenuesModel(api: ScenarioVenueService(scenario: .offlineThenRecovers),
                                snapshot: ScenarioVenueService.fixtureVenues)
        await model.load(model.request)
        #expect(model.snapshotBanner == .offline)

        model.retry()
        await model.load(model.request)
        #expect(model.phase == .loaded)
        #expect(model.snapshotBanner == nil)
        #expect(model.venues.map(\.id) == ["fixture-roasters", "fixture-library", "fixture-corner"])
    }

    @Test func withoutASnapshotColdStartIsUnchanged() async throws {
        let api = ControlledVenueService()
        let model = VenuesModel(api: api)
        let load = Task { await model.load(model.request) }
        try await api.waitForRequest(key: "any")
        #expect(model.venues.isEmpty)
        #expect(!model.isShowingSnapshot)
        #expect(model.snapshotBanner == nil)
        load.cancel()
        await load.value
    }

    @Test func engineFailureLandsInFailedPhase() async {
        let model = VenuesModel(api: ScenarioVenueService(scenario: .engineDown))

        await model.load(model.request)

        guard case .failed = model.phase else {
            Issue.record("expected .failed, got \(model.phase)")
            return
        }
        #expect(model.venues.isEmpty)
    }

    @Test func offlineLandsInTheSameFailedPhase() async {
        let model = VenuesModel(api: ScenarioVenueService(scenario: .offline))

        await model.load(model.request)

        guard case .failed = model.phase else {
            Issue.record("expected .failed, got \(model.phase)")
            return
        }
    }

    @Test func emptyAnswerIsLoadedNotFailed() async {
        let model = VenuesModel(api: ScenarioVenueService(scenario: .emptyVenues))

        await model.load(model.request)

        #expect(model.phase == .loaded)
        #expect(model.venues.isEmpty)
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
        // Filters never reach the wire (brewdesk#77) — distinct requests are
        // driven by the query coordinate instead.
        let key = query.lat == VenuesModel.coverageCenterLat ? "any" : "moved"
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
        // Deadline, not iteration count: 1ms sleeps stretch under parallel
        // test load and a 1s budget flaked (cold-simulator baseline runs).
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
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

@Suite @MainActor struct CoverageFallbackTests {
    private let cupertino = (lat: 37.3230, lng: -122.0322)

    @Test func rejectsCoordinatesOutsideCoverage() {
        let model = VenuesModel(api: ControlledVenueService())

        #expect(!model.updateCenterIfNeeded(lat: cupertino.lat, lng: cupertino.lng))
        #expect(model.isOutsideCoverage)
        // Query still targets the NYC coverage anchor, never the far coordinate.
        #expect(model.request.query.lat == VenuesModel.coverageCenterLat)
        #expect(model.request.query.lng == VenuesModel.coverageCenterLng)
    }

    @Test func acceptsCoordinatesInsideCoverage() {
        let model = VenuesModel(api: ControlledVenueService())

        #expect(model.updateCenterIfNeeded(lat: 40.6782, lng: -73.9442)) // Brooklyn
        #expect(!model.isOutsideCoverage)
        #expect(model.request.query.lat == 40.6782)
    }

    @Test func coverageFlagClearsWhenLocationReturnsInside() {
        let model = VenuesModel(api: ControlledVenueService())

        #expect(!model.updateCenterIfNeeded(lat: cupertino.lat, lng: cupertino.lng))
        #expect(model.isOutsideCoverage)
        #expect(model.updateCenterIfNeeded(lat: 40.71, lng: -74.0))
        #expect(!model.isOutsideCoverage)
    }

    @Test func browseCoverageCenterSnapsBackAndReQueries() {
        let model = VenuesModel(api: ControlledVenueService())

        #expect(model.updateCenterIfNeeded(lat: 40.6782, lng: -73.9442))
        let before = model.request.revision
        model.browseCoverageCenter()
        #expect(model.request.query.lat == VenuesModel.coverageCenterLat)
        #expect(model.request.query.lng == VenuesModel.coverageCenterLng)
        #expect(model.request.revision != before)
    }
}

@Suite @MainActor struct ProvenanceStampTests {
    private func claim(_ source: String, _ observedAt: String) -> Claim {
        Claim(value: "ok", source: source, confidence: 0.8, observedAt: observedAt)
    }

    @Test func newestClaimWinsAcrossAttributes() {
        let attributes = VenueAttributes(
            wifi: claim("agent", "2026-08-01T00:00:00Z"),
            outlets: claim("curated", "2026-08-15T00:00:00Z"),
            laptopPolicy: claim("estimate", "2026-07-01T00:00:00Z"),
            noise: claim("agent", "2026-06-01T00:00:00Z")
        )
        let newest = ProvenanceStamp.newestClaim(in: attributes)
        #expect(newest?.source == "curated")
    }

    @Test func malformedDatesRenderNothing() {
        let attributes = VenueAttributes(
            wifi: claim("agent", "soon"),
            outlets: claim("agent", ""),
            laptopPolicy: claim("agent", "n/a"),
            noise: claim("agent", "??")
        )
        #expect(ProvenanceStamp.newestClaim(in: attributes) == nil)
    }

    @Test func humanSourcesEarnTheSealAgentDoesNot() {
        #expect(ProvenanceStamp.humanSources.contains("site_visit"))
        #expect(ProvenanceStamp.humanSources.contains("curated"))
        #expect(!ProvenanceStamp.humanSources.contains("agent"))
        #expect(!ProvenanceStamp.humanSources.contains("estimate"))
    }
}

@Suite @MainActor struct HealthLoadTests {
    struct HealthyService: VenueListing {
        func fetchVenues(_ query: VenueQuery) async throws -> [Venue] { [] }
        func fetchHealth() async throws -> HealthResponse? {
            HealthResponse(ok: true, venueCount: 127, seededAt: "2026-08-15T00:00:00Z", observationCount: 480)
        }
    }
    struct FailingHealthService: VenueListing {
        func fetchVenues(_ query: VenueQuery) async throws -> [Venue] { [] }
        func fetchHealth() async throws -> HealthResponse? { throw VenueAPIError.invalidResponse }
    }

    @Test func loadHealthPopulatesStats() async {
        let model = VenuesModel(api: HealthyService())
        await model.loadHealth()
        #expect(model.health?.venueCount == 127)
        #expect(model.health?.observationCount == 480)
    }

    @Test func healthFailureStaysNilWithoutError() async {
        let model = VenuesModel(api: FailingHealthService())
        await model.loadHealth()
        #expect(model.health == nil)
        #expect(model.phase == .idle)
    }

    @Test func defaultProtocolHealthIsNil() async {
        let model = VenuesModel(api: ControlledVenueService())
        await model.loadHealth()
        #expect(model.health == nil)
    }

    nonisolated final class CountingHealthService: VenueListing, @unchecked Sendable {
        private let lock = NSLock()
        private var stored = 0
        var failing: Bool
        init(failing: Bool = false) { self.failing = failing }
        var fetches: Int { lock.withLock { stored } }
        func fetchVenues(_ query: VenueQuery) async throws -> [Venue] { [] }
        func fetchHealth() async throws -> HealthResponse? {
            lock.withLock { stored += 1 }
            if failing { throw VenueAPIError.invalidResponse }
            return HealthResponse(ok: true, venueCount: 1, seededAt: "2026-08-15T00:00:00Z", observationCount: nil)
        }
    }

    @Test func loadHealthIfNeededFetchesOnce() async {
        let service = CountingHealthService()
        let model = VenuesModel(api: service)
        await model.loadHealthIfNeeded()
        await model.loadHealthIfNeeded()
        #expect(service.fetches == 1)
        #expect(model.health?.venueCount == 1)
    }

    @Test func loadHealthIfNeededRetriesAfterFailure() async {
        let service = CountingHealthService(failing: true)
        let model = VenuesModel(api: service)
        await model.loadHealthIfNeeded()
        #expect(model.health == nil)
        service.failing = false
        await model.loadHealthIfNeeded()
        #expect(service.fetches == 2)
        #expect(model.health != nil)
    }
}

@Suite @MainActor struct SchemaV2FilterTests {
    @Test func categoryFiltersNeverReachTheQuery() {
        // brewdesk#77 — filtering is local; the wire predicate (store.ts)
        // fails unknown values and emptied the list.
        let model = VenuesModel(api: ControlledVenueService())
        model.minSeating = .plenty
        model.venueType = .library
        model.minWifi = .fast
        model.minOutlets = .plenty
        model.laptopFriendlyOnly = true
        #expect(model.request.query.seatingMinimum == nil)
        #expect(model.request.query.venueType == nil)
        #expect(model.request.query.wifiMinimum == nil)
        #expect(model.request.query.outletMinimum == nil)
        #expect(!model.request.query.laptopFriendlyOnly)
    }

    @Test func seatingCycleMirrorsOutletCycle() {
        let model = VenuesModel(api: ControlledVenueService())
        model.cycleSeatingMinimum()
        #expect(model.minSeating == .some)
        model.cycleSeatingMinimum()
        #expect(model.minSeating == .plenty)
        model.cycleSeatingMinimum()
        #expect(model.minSeating == nil)
    }
}

@Suite @MainActor struct TakeoutImportTests {
    private func venue(_ id: String, _ name: String, lat: Double, lng: Double) -> Venue {
        Venue(
            id: id, name: name, lat: lat, lng: lng, address: nil,
            neighborhood: "SoHo", borough: "Manhattan", hoursRaw: nil, vertical: "cafe",
            attributes: VenueAttributes(
                wifi: Claim(value: "ok", source: "agent", confidence: 0.5, observedAt: "2026-08-01T00:00:00Z"),
                outlets: Claim(value: "some", source: "agent", confidence: 0.5, observedAt: "2026-08-01T00:00:00Z"),
                laptopPolicy: Claim(value: "unrestricted", source: "agent", confidence: 0.5, observedAt: "2026-08-01T00:00:00Z"),
                noise: Claim(value: "moderate", source: "agent", confidence: 0.5, observedAt: "2026-08-01T00:00:00Z")
            ),
            vibeTags: [], workScore: 75, lastVerified: nil, distanceM: nil
        )
    }

    @Test func parsesTakeoutCSVWithQuotedTitlesAndURLCoords() throws {
        let csv = """
        Title,Note,URL
        "Qahwah House, W Village",,https://www.google.com/maps/place/Qahwah/@40.7301,-74.0032,17z/data=!3d40.7301!4d-74.0032
        787 Coffee,,https://maps.google.com/?cid=123
        """
        let places = try TakeoutParser.parse(Data(csv.utf8))
        #expect(places.count == 2)
        #expect(places[0].name == "Qahwah House, W Village")
        #expect(places[0].lat == 40.7301)
        #expect(places[1].lat == nil)
    }

    @Test func parsesTakeoutGeoJSON() throws {
        let geojson = """
        {"type":"FeatureCollection","features":[
          {"geometry":{"type":"Point","coordinates":[-74.0032,40.7301]},
           "properties":{"location":{"name":"Qahwah House"},"google_maps_url":"http://maps.google.com/?cid=1"}}
        ]}
        """
        let places = try TakeoutParser.parse(Data(geojson.utf8))
        #expect(places == [TakeoutPlace(name: "Qahwah House", lat: 40.7301, lng: -74.0032)])
    }

    @Test func malformedFileThrowsNotCrashes() {
        #expect(throws: TakeoutImportError.unrecognizedFormat) {
            _ = try TakeoutParser.parse(Data("not a takeout file".utf8))
        }
    }

    @Test func matchesByNameAndByProximityButNotStrangers() {
        let venues = [
            venue("v1", "Qahwah House Coffee", lat: 40.7301, lng: -74.0032),
            venue("v2", "787 Coffee", lat: 40.7280, lng: -73.9990)
        ]
        let places = [
            TakeoutPlace(name: "qahwah house"),                          // name containment
            TakeoutPlace(name: "Mystery Spot", lat: 40.72801, lng: -73.99901), // ~2m away
            TakeoutPlace(name: "Blue Bottle Chelsea", lat: 40.7465, lng: -74.0014) // stranger
        ]
        let result = TakeoutMatcher.match(places: places, venues: venues)
        #expect(result.matched.map(\.id) == ["v1", "v2"])
        #expect(result.unmatched.map(\.name) == ["Blue Bottle Chelsea"])
    }

    @Test func reImportAddsNoDuplicates() {
        let store = SavedVenuesStore(persistence: InMemoryPersistence())
        let venues = [venue("v1", "Qahwah House", lat: 40.73, lng: -74.0)]
        for _ in 0..<2 {
            let result = TakeoutMatcher.match(places: [TakeoutPlace(name: "Qahwah House")], venues: venues)
            for matched in result.matched where !store.contains(matched.id) {
                store.toggle(matched.id)
            }
        }
        #expect(store.venueIDs == ["v1"])
    }
}

@MainActor
final class InMemoryPersistence: SavedVenuePersisting {
    private var ids: [String] = []
    func loadVenueIDs() -> [String] { ids }
    func saveVenueIDs(_ venueIDs: [String]) { ids = venueIDs }
}
