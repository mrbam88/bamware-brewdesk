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
        #expect(model.venues.count == 4)
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
        #expect(model.venues.count == 4)
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
        #expect(model.venues.map(\.id) == ["fixture-roasters", "fixture-library", "fixture-corner", "fixture-unchecked"])
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

    @Test func searchNeverReachesTheQuery() {
        // brewdesk#78 — search is local over the loaded list; typing and
        // submitting must never change the request the UI reloads on.
        let model = VenuesModel(api: ControlledVenueService())
        let request = model.request

        model.searchQuery = "  espresso  "
        #expect(model.request == request)

        model.submitSearch()
        #expect(model.request == request)

        model.clearSearch()
        #expect(model.searchQuery.isEmpty)
        #expect(model.request == request)
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

    // MARK: - Viewport-driven fetch (bd#192)

    @Test func updateViewportClampsRadiusAndChangesTheRequest() {
        let model = VenuesModel(api: ControlledVenueService())
        let before = model.request

        #expect(model.updateViewport(lat: 40.71, lng: -74.0, radiusM: 50))
        #expect(model.radiusM == VenuesModel.minRadiusM)
        #expect(model.request.query.lat == 40.71)
        #expect(model.request.query.lng == -74.0)
        #expect(model.request.query.radiusM == VenuesModel.minRadiusM)
        #expect(model.request != before)

        #expect(model.updateViewport(lat: 40.71, lng: -74.0, radiusM: 10_000))
        #expect(model.radiusM == VenuesModel.maxRadiusM)
    }

    @Test func updateViewportIsANoOpWhenNothingChanged() {
        let model = VenuesModel(api: ControlledVenueService())
        model.updateViewport(lat: 40.71, lng: -74.0, radiusM: 800)
        let settled = model.request

        #expect(!model.updateViewport(lat: 40.71, lng: -74.0, radiusM: 800))
        #expect(model.request == settled)
    }

    @Test func requestDefaultsToTheRaisedViewportLimit() {
        let model = VenuesModel(api: ControlledVenueService())
        #expect(model.request.query.limit == VenuesModel.viewportQueryLimit)
    }

    @Test func browseCoverageCenterResetsTheRadiusToo() {
        let model = VenuesModel(api: ControlledVenueService())
        model.updateViewport(lat: 40.71, lng: -74.0, radiusM: 400)
        #expect(model.radiusM == 400)

        model.browseCoverageCenter()

        #expect(model.radiusM == VenuesModel.defaultRadiusM)
        #expect(model.centerLat == VenuesModel.coverageCenterLat)
        #expect(model.centerLng == VenuesModel.coverageCenterLng)
    }

    // MARK: - Centre source (bd#198)
    //
    // Root cause: a passive GPS tick (`updateCenterIfNeeded`) used to accept
    // ANY differing coordinate unconditionally, so it could silently
    // overwrite a centre the user had just explored via "Search this area".
    // `centerSource`/`followsUser` are what now gate that.

    @Test func firstFixOnColdStartAlwaysApplies() {
        let model = VenuesModel(api: ControlledVenueService())
        #expect(model.centerSource == .coverageDefault)

        #expect(model.updateCenterIfNeeded(lat: 40.71, lng: -74.0))

        #expect(model.centerLat == 40.71)
        #expect(model.centerLng == -74.0)
        #expect(model.centerSource == .userLocation)
        #expect(model.followsUser)
    }

    @Test func passiveUpdateAfterUpdateViewportDoesNotMoveTheCentre() {
        let model = VenuesModel(api: ControlledVenueService())
        model.updateCenterIfNeeded(lat: 40.71, lng: -74.0)              // cold-start fix
        model.updateViewport(lat: 40.72, lng: -73.99, radiusM: 500)     // "Search this area"
        #expect(model.centerSource == .exploredViewport)
        #expect(!model.followsUser)

        // A GPS tick far enough away that, pre-fix, would have overwritten
        // the explored viewport outright.
        #expect(!model.updateCenterIfNeeded(lat: 40.9, lng: -73.5))

        #expect(model.centerLat == 40.72)
        #expect(model.centerLng == -73.99)
    }

    @Test func passiveUpdateAfterCenterOnUserDoesMoveTheCentre() {
        let model = VenuesModel(api: ControlledVenueService())
        model.updateCenterIfNeeded(lat: 40.71, lng: -74.0)              // cold-start fix
        model.updateViewport(lat: 40.72, lng: -73.99, radiusM: 500)     // explore away
        #expect(model.centerOnUser(lat: 40.73, lng: -73.98, radiusM: 400)) // locate-me
        #expect(model.centerSource == .userLocation)
        #expect(model.followsUser)

        #expect(model.updateCenterIfNeeded(lat: 40.9, lng: -73.5))

        #expect(model.centerLat == 40.9)
        #expect(model.centerLng == -73.5)
    }

    @Test func passiveUpdateAfterBrowseCoverageCenterDoesNotMoveTheCentre() {
        let model = VenuesModel(api: ControlledVenueService())
        model.updateCenterIfNeeded(lat: 40.71, lng: -74.0)              // cold-start fix
        model.browseCoverageCenter()
        #expect(model.centerSource == .coverageDefault)
        #expect(!model.followsUser)

        #expect(!model.updateCenterIfNeeded(lat: 40.9, lng: -73.5))

        #expect(model.centerLat == VenuesModel.coverageCenterLat)
        #expect(model.centerLng == VenuesModel.coverageCenterLng)
    }

    /// bd#198 spec decision: "Browse NYC" is sticky against GPS even before
    /// any real fix has ever landed — the cold-start exception is for the
    /// very first GPS answer, not for every launch that happens to call
    /// Browse NYC first.
    @Test func browseCoverageCenterBeforeAnyFixStaysStickyAgainstGPS() {
        let model = VenuesModel(api: ControlledVenueService())
        model.browseCoverageCenter()

        #expect(!model.updateCenterIfNeeded(lat: 40.9, lng: -73.5))
        #expect(model.centerLat == VenuesModel.coverageCenterLat)
    }

    /// Avoids a refetch storm while walking: a fix under the follow
    /// threshold, while following, is a no-op rather than a new request.
    @Test func smallMovesWhileFollowingDoNotRefetch() {
        let model = VenuesModel(api: ControlledVenueService())
        // Distinct from `VenuesModel.coverageCenterLat/Lng` on purpose — a
        // first fix that happened to coincide with the fallback would make
        // the very next assertion's "did it move" check meaningless.
        model.updateCenterIfNeeded(lat: 40.71, lng: -74.0)

        #expect(!model.updateCenterIfNeeded(lat: 40.71001, lng: -74.0)) // ~1m
        #expect(model.centerLat == 40.71)

        #expect(model.updateCenterIfNeeded(lat: 40.7146, lng: -74.0))   // ~510m — over threshold
        #expect(model.centerLat == 40.7146)
    }

    @Test func centerOnUserAlwaysReArmsFollowingEvenWithoutMoving() {
        let model = VenuesModel(api: ControlledVenueService())
        model.updateCenterIfNeeded(lat: 40.71, lng: -74.0)
        model.updateViewport(lat: 40.71, lng: -74.0, radiusM: 500) // stays put, but stops following
        #expect(!model.followsUser)

        // centerOnUser re-arms following even though the coordinate itself
        // doesn't change — a tap is still an explicit "resume following".
        _ = model.centerOnUser(lat: 40.71, lng: -74.0, radiusM: 500)
        #expect(model.centerSource == .userLocation)
        #expect(model.followsUser)
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
    private enum TestError: Error { case failed }
    private enum Outcome { case success, failure }
    private var requests: Set<String> = []
    private var outcomes: [String: Outcome] = [:]
    /// Continuations parked by `waitForRequest`, resumed by `fetchVenues`
    /// itself the instant it records the matching key — event-driven, not
    /// polled against a deadline.
    ///
    /// bd#226/staleFailureCannotReplaceNewerSuccess CI investigation: even
    /// the 30s poll-deadline this replaced (`ContinuousClock.now + .seconds(30)`,
    /// 1ms-sleep loop) was observed timing out — "Caught error: .timedOut"
    /// (GH Actions run 35770125411, commit 1c9ca46) — once the full
    /// BrewDeskKit-Package suite's parallel `@MainActor` test load was heavy
    /// enough to starve this actor for longer than any fixed wall-clock
    /// budget. The production code was never late; the deadline was just
    /// too tight for the scheduler pressure of ~340 tests running together.
    /// Because this actor serializes `fetchVenues` and `waitForRequest`,
    /// there's no race between "insert the key" and "park a continuation for
    /// it" — whichever call reaches the actor first is handled correctly, so
    /// waiting on the real event instead of a deadline removes the flake
    /// entirely rather than just widening the margin again.
    private var requestContinuations: [String: [CheckedContinuation<Void, Never>]] = [:]

    func fetchVenues(_ query: VenueQuery) async throws -> [Venue] {
        // Filters never reach the wire (brewdesk#77) — distinct requests are
        // driven by the query coordinate instead.
        let key = query.lat == VenuesModel.coverageCenterLat ? "any" : "moved"
        requests.insert(key)
        resumeRequestWaiters(for: key)
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

    /// Suspends until `fetchVenues` has recorded a request for `key`. Never
    /// times out — see `requestContinuations` above for why that's the
    /// point, not an oversight. `throws` is kept on the signature purely so
    /// every existing `try await api.waitForRequest(...)` call site needs no
    /// edit; the body itself never throws.
    func waitForRequest(key: String) async throws {
        guard !requests.contains(key) else { return }
        await withCheckedContinuation { continuation in
            requestContinuations[key, default: []].append(continuation)
        }
    }

    private func resumeRequestWaiters(for key: String) {
        guard let continuations = requestContinuations.removeValue(forKey: key) else { return }
        for continuation in continuations { continuation.resume() }
    }

    func succeed(key: String) {
        outcomes[key] = .success
    }

    func fail(key: String) {
        outcomes[key] = .failure
    }
}

/// bd#108: the client no longer rejects or re-anchors a coordinate far from
/// NYC — it always queries the real viewport (brewdesk#1's "outside NYC"
/// fallback removed). `CoverageStateTests` below covers the coverage-driven
/// banner/empty-state contract that replaced it.
@Suite @MainActor struct RealViewportTests {
    private let cupertino = (lat: 37.3230, lng: -122.0322)

    @Test func aCoordinateFarFromNYCIsAcceptedLikeAnyOther() {
        let model = VenuesModel(api: ControlledVenueService())

        #expect(model.updateCenterIfNeeded(lat: cupertino.lat, lng: cupertino.lng))
        #expect(model.request.query.lat == cupertino.lat)
        #expect(model.request.query.lng == cupertino.lng)
    }

    @Test func aCoordinateInsideNYCIsAcceptedTheSameWay() {
        let model = VenuesModel(api: ControlledVenueService())

        #expect(model.updateCenterIfNeeded(lat: 40.6782, lng: -73.9442)) // Brooklyn
        #expect(model.request.query.lat == 40.6782)
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

/// ve#46's `coverage` field, as surfaced through `VenuesModel.coverage`
/// (bd#108) — drives the map's baseline banner and, when `.none`, the
/// existing empty state (no new UI for `.none`; `venues.isEmpty` already
/// covers it).
@Suite @MainActor struct CoverageStateTests {
    @Test func missingCoverageDefaultsToResearched() async throws {
        // ControlledVenueService only implements `fetchVenues` — the
        // protocol's default `fetchVenuesResult` extension answers
        // `.researched`, exactly like a pre-ve#46 engine response.
        // (It blocks until the test resumes it — drive it like its siblings,
        // otherwise the test hangs the whole package run.)
        let api = ControlledVenueService()
        let model = VenuesModel(api: api)
        let request = model.request
        let load = Task { await model.load(request) }
        try await api.waitForRequest(key: "any")
        await api.succeed(key: "any")
        await load.value
        #expect(model.coverage == .researched)
    }

    @Test func baselineCoverageIsSurfacedWithFiveOrMoreVenues() async {
        let model = VenuesModel(api: ScenarioVenueService(scenario: .baselineCity))
        await model.load(model.request)
        #expect(model.coverage == .baseline)
        #expect(model.venues.count >= 5)
        #expect(model.venues.allSatisfy { $0.isOSMBaseline })
    }

    @Test func noCoverageIsSurfacedAsALoadedEmptyResult() async {
        let model = VenuesModel(api: ScenarioVenueService(scenario: .noCoverage))
        await model.load(model.request)
        #expect(model.coverage == .none)
        #expect(model.venues.isEmpty)
        #expect(model.phase == .loaded)
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

    /// ve#46 / bd#108: the "OSM baseline · updated <date>" wording triggers
    /// on either signal — a venue tiered `osm-baseline`, or a claim itself
    /// sourced `osm` — never on curated/agent claims for a researched venue.
    @Test func osmBaselineWordingTriggersOnTierOrClaimSource() {
        #expect(ProvenanceStamp.isOSMBaseline(tier: "osm-baseline", source: "curated"))
        #expect(ProvenanceStamp.isOSMBaseline(tier: nil, source: "osm"))
        #expect(!ProvenanceStamp.isOSMBaseline(tier: nil, source: "curated"))
        #expect(!ProvenanceStamp.isOSMBaseline(tier: "researched", source: "agent"))
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

/// bd#200 — "Search must be city-wide". Root cause: `venues` was a purely
/// LOCAL filter over `loadedVenues` (the current viewport's ≤500 pins
/// within ≤3km), so a café outside that viewport — however exact the typed
/// name — could never appear. These pin the new, SEPARATE citywide server
/// search (`q=<text>` over a 40km radius) that widens `venues` alongside
/// the unchanged instant local filter.
@Suite @MainActor struct CityWideSearchTests {
    private func venue(
        id: String, name: String,
        lat: Double = VenuesModel.coverageCenterLat, lng: Double = VenuesModel.coverageCenterLng,
        neighborhood: String = "Union Square"
    ) -> Venue {
        let observedAt = "2026-08-01T00:00:00Z"
        let claim = Claim(value: "fast", source: "curated", confidence: 0.9, observedAt: observedAt)
        return Venue(
            id: id, name: name, lat: lat, lng: lng, address: nil,
            neighborhood: neighborhood, borough: "Manhattan", hoursRaw: nil, vertical: "cafe",
            attributes: VenueAttributes(wifi: claim, outlets: claim, laptopPolicy: claim, noise: claim),
            vibeTags: [], workScore: 70, lastVerified: nil, distanceM: nil
        )
    }

    private func loadedModel(_ api: SearchControlledService) async -> VenuesModel {
        let model = VenuesModel(api: api)
        await model.load(model.request)
        return model
    }

    // bd#226 CI investigation: 20s default, not 5s — matches the
    // ControlledVenueService/SearchControlledService deadlines above; the
    // full suite's parallel @MainActor load can push real scheduling delays
    // well past a tight budget without the production code being at fault.
    private func poll(timeout: TimeInterval = 20, _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(Int(timeout))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("timed out waiting for condition")
    }

    @Test func serverResultAppearsForANameNotInLoadedVenues() async throws {
        // The bug, reproduced: "Conwell" is nowhere in the loaded viewport.
        let local = [venue(id: "local-1", name: "Fixture Roasters")]
        let conwell = venue(
            id: "conwell", name: "Conwell Coffee Hall",
            lat: 40.7139, lng: -74.0090, neighborhood: "Financial District"
        )
        let api = SearchControlledService(localVenues: local)
        let model = await loadedModel(api)

        model.searchQuery = "conwell"
        model.submitSearch()
        #expect(model.venues.isEmpty)                 // local alone has nothing — not yet fixed
        #expect(model.isSearchingServer)

        try await api.waitForSearchRequest("conwell")
        await api.succeed("conwell", with: [conwell])

        try await poll { model.venues.map(\.id) == ["conwell"] }
        #expect(model.venues.map(\.id) == ["conwell"])
        #expect(!model.isSearchingServer)
    }

    @Test func staleResponseIsDroppedWhenASecondQuerySupersedesIt() async throws {
        let api = SearchControlledService(localVenues: [])
        let model = await loadedModel(api)

        model.searchQuery = "aaa"
        model.submitSearch()
        try await api.waitForSearchRequest("aaa")

        model.searchQuery = "bbb"
        model.submitSearch()
        try await api.waitForSearchRequest("bbb")

        // Resolve the SUPERSEDED query after the newer one is already
        // in flight — its answer must never reach `venues`.
        await api.succeed("aaa", with: [venue(id: "aaa-result", name: "Aaa Cafe")])
        await api.succeed("bbb", with: [venue(id: "bbb-result", name: "Bbb Cafe")])

        try await poll { model.venues.map(\.id) == ["bbb-result"] }
        #expect(model.venues.map(\.id) == ["bbb-result"])
    }

    @Test func clearingRestoresTheViewportSetWithoutWaitingOnTheServer() async throws {
        let local = [
            venue(id: "local-1", name: "Fixture Roasters"),
            venue(id: "local-2", name: "Fixture Library"),
        ]
        let api = SearchControlledService(localVenues: local)
        let model = await loadedModel(api)

        model.searchQuery = "roasters"
        model.submitSearch()
        #expect(model.venues.map(\.id) == ["local-1"])
        try await api.waitForSearchRequest("roasters")   // left unresolved on purpose

        model.clearSearch()

        #expect(model.searchQuery.isEmpty)
        #expect(Set(model.venues.map(\.id)) == Set(["local-1", "local-2"]))
        #expect(!model.isSearchingServer)                // the pending request was dropped, not awaited
    }

    /// bd#219: reproduces `selectSearchResult`'s own downstream effect —
    /// `scheduleSurroundingsLoad` calls `model.updateViewport(...)` for the
    /// selected café's location, and `DiscoveryRootView`'s
    /// `.task(id: request)` then loads it, exactly like a real
    /// "Search this area"/locate-me viewport change already does. Clearing
    /// the search afterward must show THAT newly loaded surroundings set,
    /// never the original viewport's venues re-appearing on top of the new
    /// camera position.
    @Test func clearingSearchAfterASelectionKeepsTheExploredSurroundings() async throws {
        let local = [venue(id: "local-1", name: "Fixture Roasters")]
        let farCafe = venue(
            id: "far-cafe", name: "Fixture Ferry Roasters",
            lat: 40.6437, lng: -74.0787, neighborhood: "St. George"
        )
        let farNeighbor = venue(
            id: "far-neighbor", name: "Ferry Terminal Coffee",
            lat: 40.6440, lng: -74.0790, neighborhood: "St. George"
        )
        let api = SelectionSurroundingsService(initialVenues: local, surroundingsVenues: [farCafe, farNeighbor])
        let model = VenuesModel(api: api)
        await model.load(model.request)
        #expect(model.venues.map(\.id) == ["local-1"])

        model.searchQuery = "ferry"
        model.submitSearch()
        try await api.waitForSearchRequest("ferry")
        await api.succeedSearch("ferry", with: [farCafe])
        try await poll { model.venues.map(\.id) == ["far-cafe"] }

        // The selection's own surroundings reload.
        #expect(model.updateViewport(lat: farCafe.lat, lng: farCafe.lng, radiusM: 500))
        #expect(model.centerSource == .exploredViewport)
        await model.load(model.request)
        try await poll { Set(model.venues.map(\.id)) == Set(["far-cafe", "far-neighbor"]) }

        model.clearSearch()

        #expect(model.searchQuery.isEmpty)
        #expect(
            Set(model.venues.map(\.id)) == Set(["far-cafe", "far-neighbor"]),
            "clearing the search after a selection must keep the newly explored surroundings"
        )
        #expect(
            !model.venues.map(\.id).contains("local-1"),
            "the original viewport set must not be restored on top of the new (Brooklyn) camera"
        )
    }

    @Test func unionDeduplicatesAndOrdersPrefixMatchesFirstThenByDistance() async throws {
        // "near" is loaded locally AND comes back from the server (as a
        // distinct value with the same id) — must appear exactly once.
        let near = venue(id: "near", name: "Prefix Cafe Near", lat: 40.7360, lng: -73.9912)
        let farPrefix = venue(id: "far", name: "Prefix Cafe Far", lat: 40.80, lng: -73.95, neighborhood: "Uptown")
        let containsMatch = venue(id: "contains", name: "A Prefix-Adjacent Diner", lat: 40.7361, lng: -73.9913)
        let duplicateOfNear = venue(id: "near", name: "Prefix Cafe Near", lat: 40.7360, lng: -73.9912)

        let api = SearchControlledService(localVenues: [near])
        let model = await loadedModel(api)

        model.searchQuery = "prefix"
        model.submitSearch()
        try await api.waitForSearchRequest("prefix")
        await api.succeed("prefix", with: [duplicateOfNear, farPrefix, containsMatch])

        try await poll { model.venues.count == 3 }
        // De-duped to one "near"; prefix matches ("near", "far") rank
        // before the contains match; the nearer prefix match wins first.
        #expect(model.venues.map(\.id) == ["near", "far", "contains"])
    }

    @Test func networkFailureKeepsLocalResultsAndFlagsTheFailure() async throws {
        let local = [venue(id: "local-1", name: "Prefix Cafe")]
        let api = SearchControlledService(localVenues: local)
        let model = await loadedModel(api)

        model.searchQuery = "prefix"
        model.submitSearch()
        #expect(model.venues.map(\.id) == ["local-1"])   // instant local match, unaffected

        try await api.waitForSearchRequest("prefix")
        await api.fail("prefix")

        try await poll { !model.isSearchingServer }
        #expect(model.serverSearchFailed)
        #expect(model.venues.map(\.id) == ["local-1"])   // still there — never cleared on failure
    }

    @Test func belowMinimumLengthNeverFiresARequest() async throws {
        let api = SearchControlledService(localVenues: [])
        let model = await loadedModel(api)
        let callsAfterLoad = await api.searchCallCount

        model.searchQuery = "a"
        model.submitSearch()

        #expect(!model.isSearchingServer)
        #expect(await api.searchCallCount == callsAfterLoad)
    }
}

private actor SearchControlledService: VenueListing {
    private enum TestError: Error { case timedOut }
    private let localVenues: [Venue]
    private var pendingRequests: Set<String> = []
    private var outcomes: [String: Result<[Venue], Error>] = [:]
    private(set) var searchCallCount = 0

    init(localVenues: [Venue]) {
        self.localVenues = localVenues
    }

    func fetchVenues(_ query: VenueQuery) async throws -> [Venue] { localVenues }

    /// A `search`-less call (the viewport load `VenuesModel.load` always
    /// makes) answers immediately with `localVenues`. A `search` call
    /// blocks until the test resolves it via `succeed`/`fail`, keyed by the
    /// exact search text — mirrors `ControlledVenueService` above, scoped
    /// to bd#200's separate citywide request.
    func fetchVenuesResult(_ query: VenueQuery) async throws -> VenueLoadResult {
        guard let search = query.search, !search.isEmpty else {
            return VenueLoadResult(venues: localVenues, coverage: .researched)
        }
        searchCallCount += 1
        pendingRequests.insert(search)
        while true {
            try Task.checkCancellation()
            if let outcome = outcomes.removeValue(forKey: search) {
                switch outcome {
                case .success(let venues): return VenueLoadResult(venues: venues, coverage: .researched)
                case .failure(let error): throw error
                }
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    func waitForSearchRequest(_ text: String) async throws {
        // bd#226 CI investigation: 30s, not 10s — see ControlledVenueService
        // .waitForRequest above for why.
        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline {
            if pendingRequests.contains(text) { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw TestError.timedOut
    }

    func succeed(_ text: String, with venues: [Venue]) {
        outcomes[text] = .success(venues)
    }

    func fail(_ text: String, with error: Error = URLError(.notConnectedToInternet)) {
        outcomes[text] = .failure(error)
    }
}

/// bd#219: unlike `SearchControlledService` above (one fixed `localVenues`
/// set for every viewport fetch), this varies the VIEWPORT answer by
/// coordinate — `initialVenues` at the model's starting coverage-default
/// center, `surroundingsVenues` for any other center — so a test can prove
/// what actually loads once a selection's surroundings reload
/// (`model.updateViewport` + a re-`load`) moves the viewport to a whole new
/// location, not just what a citywide search widened `venues` with locally.
private actor SelectionSurroundingsService: VenueListing {
    private enum TestError: Error { case timedOut }
    private let initialVenues: [Venue]
    private let surroundingsVenues: [Venue]
    private var pendingSearch: Set<String> = []
    private var searchOutcomes: [String: [Venue]] = [:]

    init(initialVenues: [Venue], surroundingsVenues: [Venue]) {
        self.initialVenues = initialVenues
        self.surroundingsVenues = surroundingsVenues
    }

    private func venues(for query: VenueQuery) -> [Venue] {
        query.lat == VenuesModel.coverageCenterLat && query.lng == VenuesModel.coverageCenterLng
            ? initialVenues : surroundingsVenues
    }

    func fetchVenues(_ query: VenueQuery) async throws -> [Venue] { venues(for: query) }

    func fetchVenuesResult(_ query: VenueQuery) async throws -> VenueLoadResult {
        guard let search = query.search, !search.isEmpty else {
            return VenueLoadResult(venues: venues(for: query), coverage: .researched)
        }
        pendingSearch.insert(search)
        while true {
            try Task.checkCancellation()
            if let result = searchOutcomes.removeValue(forKey: search) {
                return VenueLoadResult(venues: result, coverage: .researched)
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    func waitForSearchRequest(_ text: String) async throws {
        // bd#226 CI investigation: 30s, not 10s — see ControlledVenueService
        // .waitForRequest above for why.
        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline {
            if pendingSearch.contains(text) { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw TestError.timedOut
    }

    func succeedSearch(_ text: String, with venues: [Venue]) {
        searchOutcomes[text] = venues
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

/// brewdesk#222 — `VenuesModel.confirmedVenues`/`unknownVenues`/counts/
/// `hasActiveFilter`, and the default-type ranking those sections carry.
@Suite @MainActor struct FilterSectionsTests {
    private static let observedAt = "2026-08-01T00:00:00Z"

    private static func venue(
        id: String, wifi: String, workScore: Int = 70, venueType: String? = "cafe"
    ) -> Venue {
        func claim(_ value: String) -> Claim {
            Claim(value: value, source: "curated", confidence: 0.8, observedAt: observedAt)
        }
        return Venue(
            id: id, name: id, lat: 40.7359, lng: -73.9911, address: nil,
            neighborhood: "Union Square", borough: "Manhattan", hoursRaw: nil, vertical: "cafe",
            attributes: VenueAttributes(
                wifi: claim(wifi), outlets: claim("plenty"), laptopPolicy: claim("unrestricted"),
                noise: claim("moderate"), seating: claim("plenty")
            ),
            vibeTags: [], workScore: workScore, lastVerified: nil, distanceM: nil, venueType: venueType
        )
    }

    private func loadedModel(_ venues: [Venue]) async -> VenuesModel {
        let model = VenuesModel(api: FixtureVenueService(venues: venues))
        await model.load(model.request)
        return model
    }

    @Test func noFilterMeansEveryVenueConfirmedAndNoUnknowns() async {
        let venues = [
            Self.venue(id: "a", wifi: "fast"),
            Self.venue(id: "b", wifi: "unknown"),
        ]
        let model = await loadedModel(venues)
        #expect(!model.hasActiveFilter)
        #expect(model.confirmedVenues.map(\.id) == ["a", "b"])
        #expect(model.unknownVenues.isEmpty)
        #expect(model.confirmedCount == 2)
        #expect(model.unknownCount == 0)
    }

    @Test func fastWifiFilterSplitsConfirmedAndUnknownAndExcludesKnownSlow() async {
        let venues = [
            Self.venue(id: "confirmed", wifi: "fast"),
            Self.venue(id: "unknown", wifi: "unknown"),
            Self.venue(id: "excluded", wifi: "slow"),
        ]
        let model = await loadedModel(venues)
        model.minWifi = .fast

        #expect(model.hasActiveFilter)
        #expect(model.confirmedVenues.map(\.id) == ["confirmed"])
        #expect(model.unknownVenues.map(\.id) == ["unknown"])
        #expect(model.confirmedCount == 1)
        #expect(model.unknownCount == 1)
        // The excluded venue never appears in `venues` at all (`matches`),
        // let alone either section.
        #expect(!model.venues.map(\.id).contains("excluded"))
    }

    /// Ordering within each section stays observed-first/score (item 2) —
    /// a stable filter over `venues`' own order, not a re-sort.
    @Test func sectionsPreserveTheExistingOrderWithinEachHalf() async {
        let venues = [
            Self.venue(id: "confirmed-low", wifi: "fast", workScore: 40),
            Self.venue(id: "unknown-first", wifi: "unknown", workScore: 90),
            Self.venue(id: "confirmed-high", wifi: "fast", workScore: 95),
            Self.venue(id: "unknown-second", wifi: "unknown", workScore: 10),
        ]
        let model = await loadedModel(venues)
        model.minWifi = .fast

        // `venues`' own order (server order here; nothing to re-rank on
        // score since every venue is equally "rated" in this fixture) is
        // preserved inside each split.
        #expect(model.confirmedVenues.map(\.id) == ["confirmed-low", "confirmed-high"])
        #expect(model.unknownVenues.map(\.id) == ["unknown-first", "unknown-second"])
    }

    /// The TestFlight build 28 shape: a coworking space must not lead a
    /// section purely on score once cafés are also present, while the type
    /// filter still exposes it when chosen.
    @Test func confirmedSectionRanksCafesAboveOtherTypesByDefault() async {
        let venues = [
            Self.venue(id: "wework", wifi: "fast", workScore: 90, venueType: "coworking"),
            Self.venue(id: "cafe", wifi: "fast", workScore: 40, venueType: "cafe"),
        ]
        let model = await loadedModel(venues)
        model.minWifi = .fast

        #expect(model.confirmedVenues.map(\.id) == ["cafe", "wework"])

        model.venueType = .cafe
        // Choosing a type is a no-op for the ranking rule itself; it also
        // narrows `venues` to that type via `VenueFilter`, so the coworking
        // space drops out entirely here (a separate, existing mechanism).
        #expect(model.confirmedVenues.map(\.id) == ["cafe"])
    }
}

/// Minimal fixture `VenueListing` for `FilterSectionsTests` — returns the
/// given venues for any query, unfiltered (category filtering is local to
/// `VenuesModel`/`VenueFilter`, never the wire).
private struct FixtureVenueService: VenueListing {
    let venues: [Venue]
    func fetchVenues(_ query: VenueQuery) async throws -> [Venue] { venues }
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
