import Foundation
import Testing
@testable import BrewDeskKit
import VenueKit

/// bd#267: cafés load on their own when the map comes to rest somewhere
/// new. Every test drives time through `ManualClock` — nothing here sleeps
/// on a real clock, so the 400 ms debounce and the 1 s rate limit are
/// asserted exactly, not approximately.
@Suite @MainActor struct VenuesModelAutoLoadTests {
    private static let villageLat = 40.7336
    private static let villageLng = -74.0027

    /// A walking-scale phone viewport (about 1.1 km wide, 1.7 km tall,
    /// 2.9 m/pt) centred `northM` metres north of Greenwich Village.
    private func viewport(
        northM: Double = 0, radiusM: Int = 850, spanM: Double = 1_100, metersPerPoint: Double = 2.9
    ) -> MapViewport {
        MapViewport(
            centerLat: Self.villageLat + northM / 111_320,
            centerLng: Self.villageLng,
            radiusM: radiusM,
            spanM: spanM,
            metersPerPoint: metersPerPoint
        )
    }

    private var fixtures: [Venue] { ScenarioVenueService.fixtureVenues }

    /// A model whose first, ordinary load already answered for the Village
    /// viewport with `initial` — the state every pan starts from.
    private func loadedModel(
        api: ViewportVenueService, clock: ManualClock, initial: [Venue]
    ) async throws -> VenuesModel {
        let model = VenuesModel(api: api, autoLoadTiming: clock.timing)
        model.updateViewport(lat: Self.villageLat, lng: Self.villageLng, radiusM: 850)
        let request = model.request
        let load = Task { await model.load(request) }
        try await api.waitForRequests(1)
        await api.respond(toRequest: 1, with: .success(initial))
        await load.value
        #expect(model.phase == .loaded)
        return model
    }

    // MARK: - Trigger

    @Test func panBeyondThresholdFetchesOnceAfterTheDebounce() async throws {
        let api = ViewportVenueService()
        let clock = ManualClock()
        let model = try await loadedModel(api: api, clock: clock, initial: Array(fixtures.prefix(1)))

        // 600 m north is past 35% of the 1.1 km visible span.
        let target = viewport(northM: 600)
        #expect(model.cameraSettled(target) == .scheduled)
        let task = try #require(model.autoLoadTask)

        // Nothing goes out, and nothing shows as loading, during the debounce.
        await clock.waitForSleeps(1)
        #expect(clock.requestedSleeps == [.milliseconds(400)])
        #expect(await api.requestCount == 1)
        #expect(!model.isAutoLoading)

        clock.advance(by: .milliseconds(400))
        try await api.waitForRequests(2)
        #expect(model.isAutoLoading)
        // The pins already on screen stay while it loads.
        #expect(model.venues.count == 1)

        let query = try #require(await api.query(ofRequest: 2))
        #expect(abs((query.lat ?? 0) - target.centerLat) < 1e-9)
        #expect(query.radiusM == 850)
        #expect(query.limit == VenuesModel.viewportQueryLimit)

        await api.respond(toRequest: 2, with: .success(Array(fixtures.prefix(3))))
        await task.value
        #expect(model.venues.count == 3)
        #expect(model.phase == .loaded)
        #expect(!model.isAutoLoading)
        #expect(!model.autoLoadFailed)
        #expect(model.centerSource == .exploredViewport)
        #expect(await api.requestCount == 2)

        // `DiscoveryRootView` re-runs its `.task(id: request)` because the
        // centre moved; that must not become a second fetch.
        await model.load(model.request)
        #expect(await api.requestCount == 2)
        #expect(model.venues.count == 3)
    }

    @Test func smallPanDoesNotFetch() async throws {
        let api = ViewportVenueService()
        let clock = ManualClock()
        let model = try await loadedModel(api: api, clock: clock, initial: fixtures)

        // 200 m is under 35% of the 1.1 km span, at the same zoom.
        #expect(model.cameraSettled(viewport(northM: 200)) == .withinThreshold)
        #expect(model.autoLoadTask == nil)
        #expect(clock.requestedSleeps.isEmpty)
        #expect(await api.requestCount == 1)
        #expect(model.venues.count == fixtures.count)
    }

    @Test func zoomChangeBeyondTheRatioFetchesWithoutAnyPan() async throws {
        let api = ViewportVenueService()
        let clock = ManualClock()
        let model = try await loadedModel(api: api, clock: clock, initial: fixtures)

        // Same centre; 1.5x wider is inside the 1.6x rule, 2x is outside.
        #expect(model.cameraSettled(viewport(radiusM: 1_275, spanM: 1_650, metersPerPoint: 4.4)) == .withinThreshold)
        #expect(model.cameraSettled(viewport(radiusM: 1_700, spanM: 2_200, metersPerPoint: 5.8)) == .scheduled)
        // …and zooming in by the same factor counts too.
        #expect(model.cameraSettled(viewport(radiusM: 425, spanM: 550, metersPerPoint: 1.45)) == .scheduled)
    }

    @Test func repeatedRestAtTheSamePlaceKeepsTheOneScheduledFetch() async throws {
        let api = ViewportVenueService()
        let clock = ManualClock()
        let model = try await loadedModel(api: api, clock: clock, initial: fixtures)

        #expect(model.cameraSettled(viewport(northM: 600)) == .scheduled)
        #expect(model.cameraSettled(viewport(northM: 601)) == .alreadyScheduled)
        await clock.waitForSleeps(1)
        #expect(clock.requestedSleeps.count == 1)
    }

    // MARK: - Cancellation and stale answers

    @Test func twoQuickPansOnlyFetchTheLast() async throws {
        let api = ViewportVenueService()
        let clock = ManualClock()
        let model = try await loadedModel(api: api, clock: clock, initial: fixtures)

        #expect(model.cameraSettled(viewport(northM: 600)) == .scheduled)
        await clock.waitForSleeps(1)
        clock.advance(by: .milliseconds(200))
        // The second pan lands inside the first one's debounce.
        let second = viewport(northM: 1_400)
        #expect(model.cameraSettled(second) == .scheduled)
        let task = try #require(model.autoLoadTask)
        await clock.waitForSleeps(2)
        clock.advance(by: .milliseconds(400))

        try await api.waitForRequests(2)
        let query = try #require(await api.query(ofRequest: 2))
        #expect(abs((query.lat ?? 0) - second.centerLat) < 1e-9)
        await api.respond(toRequest: 2, with: .success(Array(fixtures.prefix(2))))
        await task.value
        #expect(await api.requestCount == 2)
        #expect(model.venues.count == 2)
    }

    @Test func olderResponseIsDroppedWhenANewerPanAnswersFirst() async throws {
        let api = ViewportVenueService()
        let clock = ManualClock()
        let model = try await loadedModel(api: api, clock: clock, initial: Array(fixtures.prefix(1)))

        // First pan: its fetch goes out and hangs.
        #expect(model.cameraSettled(viewport(northM: 600)) == .scheduled)
        let firstTask = try #require(model.autoLoadTask)
        await clock.waitForSleeps(1)
        clock.advance(by: .milliseconds(400))
        try await api.waitForRequests(2)
        #expect(model.isAutoLoading)

        // Second pan while the first is in flight: the first is cancelled,
        // and the second waits out the rest of the 1 s between starts.
        clock.advance(by: .milliseconds(100))
        #expect(model.cameraSettled(viewport(northM: 1_400)) == .scheduled)
        #expect(!model.isAutoLoading)
        let secondTask = try #require(model.autoLoadTask)
        await clock.waitForSleeps(2)
        #expect(clock.requestedSleeps.last == .milliseconds(900))
        clock.advance(by: .milliseconds(900))
        try await api.waitForRequests(3)

        await api.respond(toRequest: 3, with: .success(Array(fixtures.prefix(3))))
        await secondTask.value
        #expect(model.venues.count == 3)

        // The fake ignores cancellation on purpose, so the first fetch now
        // answers LATE with a different list — the token must drop it.
        await api.respond(toRequest: 2, with: .success(fixtures))
        await firstTask.value
        #expect(model.venues.count == 3)
        #expect(model.phase == .loaded)
        #expect(!model.autoLoadFailed)
    }

    @Test func aStaleFailureCannotMarkANewerSuccessFailed() async throws {
        let api = ViewportVenueService()
        let clock = ManualClock()
        let model = try await loadedModel(api: api, clock: clock, initial: fixtures)

        #expect(model.cameraSettled(viewport(northM: 600)) == .scheduled)
        let firstTask = try #require(model.autoLoadTask)
        await clock.waitForSleeps(1)
        clock.advance(by: .milliseconds(400))
        try await api.waitForRequests(2)

        #expect(model.cameraSettled(viewport(northM: 1_400)) == .scheduled)
        let secondTask = try #require(model.autoLoadTask)
        await clock.waitForSleeps(2)
        clock.advance(by: .seconds(1))
        try await api.waitForRequests(3)
        await api.respond(toRequest: 3, with: .success(Array(fixtures.prefix(2))))
        await secondTask.value

        await api.respond(toRequest: 2, with: .failure)
        await firstTask.value
        #expect(model.phase == .loaded)
        #expect(!model.autoLoadFailed)
        #expect(model.venues.count == 2)
    }

    // MARK: - Suppression

    @Test func flyToAndSheetTransitionsSuppress() async throws {
        let api = ViewportVenueService()
        let clock = ManualClock()
        let model = try await loadedModel(api: api, clock: clock, initial: fixtures)

        // The view reports a fly-to / sheet transition / non-gesture move
        // as `suppressed`.
        #expect(model.cameraSettled(viewport(northM: 2_000), suppressed: true) == .suppressed)
        #expect(model.autoLoadTask == nil)
        #expect(clock.requestedSleeps.isEmpty)
        #expect(await api.requestCount == 1)
    }

    @Test func aFlyToCancelsAFetchStillInItsDebounce() async throws {
        let api = ViewportVenueService()
        let clock = ManualClock()
        let model = try await loadedModel(api: api, clock: clock, initial: fixtures)

        #expect(model.cameraSettled(viewport(northM: 600)) == .scheduled)
        let task = try #require(model.autoLoadTask)
        await clock.waitForSleeps(1)
        // A search result is picked: the camera flies, the view suppresses.
        #expect(model.cameraSettled(viewport(northM: 3_000), suppressed: true) == .suppressed)
        clock.advance(by: .seconds(2))
        await task.value
        #expect(await api.requestCount == 1)
        #expect(!model.isAutoLoading)
    }

    @Test func typingSuppresses() async throws {
        let api = ViewportVenueService()
        let clock = ManualClock()
        let model = try await loadedModel(api: api, clock: clock, initial: fixtures)

        // One character: under the citywide search's own 2-character
        // trigger, so the only request that could go out is an auto fetch.
        model.searchQuery = "s"
        #expect(model.cameraSettled(viewport(northM: 600)) == .suppressed)
        #expect(model.autoLoadTask == nil)
        #expect(await api.requestCount == 1)
    }

    @Test func typingThatStartsDuringTheDebounceStopsTheFetch() async throws {
        let api = ViewportVenueService()
        let clock = ManualClock()
        let model = try await loadedModel(api: api, clock: clock, initial: fixtures)

        #expect(model.cameraSettled(viewport(northM: 600)) == .scheduled)
        let task = try #require(model.autoLoadTask)
        await clock.waitForSleeps(1)
        model.searchQuery = "s"
        clock.advance(by: .milliseconds(400))
        await task.value
        #expect(await api.requestCount == 1)
        #expect(!model.isAutoLoading)
    }

    @Test func offlineSnapshotIsLeftAlone() async {
        let clock = ManualClock()
        let model = VenuesModel(
            api: ScenarioVenueService(scenario: .offline),
            snapshot: ScenarioVenueService.fixtureVenues,
            autoLoadTiming: clock.timing
        )
        await model.load(model.request)
        #expect(model.snapshotBanner == .offline)

        #expect(model.cameraSettled(viewport(northM: 2_000)) == .suppressed)
        #expect(model.autoLoadTask == nil)
        #expect(model.snapshotBanner == .offline)
        #expect(model.venues.count == 4)
    }

    // MARK: - Zoom-out rule

    @Test func zoomedOutPastTheLimitNeverFetchesAndOffersThePill() async throws {
        let api = ViewportVenueService()
        let clock = ManualClock()
        let model = try await loadedModel(api: api, clock: clock, initial: fixtures)

        // 45 m/pt: a ~17 km wide view, well past the 40 m/pt limit.
        let cityWide = viewport(northM: 4_000, radiusM: 13_000, spanM: 17_500, metersPerPoint: 45)
        #expect(model.cameraSettled(cityWide) == .zoomedOut)
        #expect(model.autoLoadBlockedByZoom)
        #expect(model.autoLoadTask == nil)
        #expect(clock.requestedSleeps.isEmpty)
        #expect(await api.requestCount == 1)

        // Zooming back in over a new area fetches and clears the flag.
        #expect(model.cameraSettled(viewport(northM: 4_000)) == .scheduled)
        #expect(!model.autoLoadBlockedByZoom)
    }

    @Test func justInsideTheZoomLimitStillFetches() async throws {
        let api = ViewportVenueService()
        let clock = ManualClock()
        let model = try await loadedModel(api: api, clock: clock, initial: fixtures)

        let wide = viewport(northM: 4_000, radiusM: 11_000, spanM: 15_000, metersPerPoint: 39)
        #expect(model.cameraSettled(wide) == .scheduled)
        let task = try #require(model.autoLoadTask)
        await clock.waitForSleeps(1)
        clock.advance(by: .milliseconds(400))
        try await api.waitForRequests(2)
        // The query radius is still clamped to what the engine accepts.
        #expect(await api.query(ofRequest: 2)?.radiusM == VenuesModel.maxRadiusM)
        await api.respond(toRequest: 2, with: .success([]))
        await task.value
    }

    // MARK: - Failure

    @Test func failureKeepsPreviousVenuesAndOffersRetry() async throws {
        let api = ViewportVenueService()
        let clock = ManualClock()
        let model = try await loadedModel(api: api, clock: clock, initial: fixtures)

        let target = viewport(northM: 600)
        #expect(model.cameraSettled(target) == .scheduled)
        let task = try #require(model.autoLoadTask)
        await clock.waitForSleeps(1)
        clock.advance(by: .milliseconds(400))
        try await api.waitForRequests(2)
        await api.respond(toRequest: 2, with: .failure)
        await task.value

        #expect(model.venues.count == fixtures.count)
        #expect(model.autoLoadFailed)
        #expect(!model.isAutoLoading)
        guard case .failed = model.phase else {
            Issue.record("expected .failed, got \(model.phase)"); return
        }

        // Retry (the pill, the error card, or a reconnect) re-asks for the
        // viewport that failed — through the ordinary load path.
        model.retry()
        let request = model.request
        #expect(abs((request.query.lat ?? 0) - target.centerLat) < 1e-9)
        let load = Task { await model.load(request) }
        try await api.waitForRequests(3)
        #expect(!model.autoLoadFailed)
        await api.respond(toRequest: 3, with: .success(Array(fixtures.prefix(2))))
        await load.value
        #expect(model.phase == .loaded)
        #expect(model.venues.count == 2)
    }

    // MARK: - No regressions

    @Test func anAutoLoadedViewportIsNeverOverwrittenByGPS() async throws {
        let api = ViewportVenueService()
        let clock = ManualClock()
        let model = VenuesModel(api: api, autoLoadTiming: clock.timing)
        // Cold start: a real fix, then the first load.
        #expect(model.updateCenterIfNeeded(lat: Self.villageLat, lng: Self.villageLng))
        let request = model.request
        let load = Task { await model.load(request) }
        try await api.waitForRequests(1)
        await api.respond(toRequest: 1, with: .success(fixtures))
        await load.value
        #expect(model.followsUser)

        let target = viewport(northM: 3_000)
        #expect(model.cameraSettled(target) == .scheduled)
        let task = try #require(model.autoLoadTask)
        // Even before the fetch starts, GPS no longer pulls the map back.
        #expect(!model.updateCenterIfNeeded(lat: Self.villageLat + 0.005, lng: Self.villageLng))
        await clock.waitForSleeps(1)
        clock.advance(by: .milliseconds(400))
        try await api.waitForRequests(2)
        await api.respond(toRequest: 2, with: .success(fixtures))
        await task.value

        #expect(!model.updateCenterIfNeeded(lat: Self.villageLat + 0.005, lng: Self.villageLng))
        #expect(abs(model.centerLat - target.centerLat) < 1e-9)
        #expect(model.centerSource == .exploredViewport)
    }

    @Test func aManualViewportLoadSupersedesAnAutoFetchInFlight() async throws {
        let api = ViewportVenueService()
        let clock = ManualClock()
        let model = try await loadedModel(api: api, clock: clock, initial: fixtures)

        #expect(model.cameraSettled(viewport(northM: 600)) == .scheduled)
        let autoTask = try #require(model.autoLoadTask)
        await clock.waitForSleeps(1)
        clock.advance(by: .milliseconds(400))
        try await api.waitForRequests(2)

        // Locate-me / a search selection / the pill: the ordinary path.
        model.updateViewport(lat: 40.78, lng: -73.96, radiusM: 900)
        #expect(!model.isAutoLoading)
        let request = model.request
        let load = Task { await model.load(request) }
        try await api.waitForRequests(3)
        await api.respond(toRequest: 3, with: .success(Array(fixtures.prefix(1))))
        await load.value

        await api.respond(toRequest: 2, with: .success(fixtures))
        await autoTask.value
        #expect(model.venues.count == 1)
        #expect(abs(model.centerLat - 40.78) < 1e-9)
    }

    // MARK: - The pure rule

    @Test func thresholdUsesTheVisibleSpan() {
        func needs(movedNorthM: Double, spanM: Double, radiusM: Int = 850) -> Bool {
            VenuesModel.viewportNeedsLoad(
                loadedLat: Self.villageLat, loadedLng: Self.villageLng, loadedRadiusM: radiusM,
                visible: viewport(northM: movedNorthM, radiusM: radiusM, spanM: spanM)
            )
        }
        // 35% of a 1,100 m span is 385 m.
        #expect(!needs(movedNorthM: 370, spanM: 1_100))
        #expect(needs(movedNorthM: 400, spanM: 1_100))
        // Zoomed far in, the span is floored at twice the minimum query
        // radius (600 m → 210 m), so tiny nudges do not refetch.
        #expect(!needs(movedNorthM: 150, spanM: 200, radiusM: 300))
        #expect(needs(movedNorthM: 230, spanM: 200, radiusM: 300))
    }
}

// MARK: - Fakes

/// Hand-driven time. `sleep` parks until `advance` moves the clock past its
/// deadline (or the sleeping task is cancelled); `now` only ever changes
/// through `advance`.
private nonisolated final class ManualClock: @unchecked Sendable {
    private struct Sleeper {
        let id: Int
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private let origin = ContinuousClock.now
    private var elapsed: Duration = .zero
    private var sleepers: [Sleeper] = []
    private var cancelledIDs: Set<Int> = []
    private var nextID = 0
    private var sleeps: [Duration] = []
    private var sleepWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    var timing: AutoLoadTiming {
        AutoLoadTiming(
            now: { [self] in now() },
            sleep: { [self] in try await sleep($0) }
        )
    }

    /// Every duration `sleep` has been asked for, in order.
    var requestedSleeps: [Duration] { lock.withLock { sleeps } }

    func now() -> ContinuousClock.Instant {
        lock.withLock { origin.advanced(by: elapsed) }
    }

    func sleep(_ duration: Duration) async throws {
        let id = lock.withLock { () -> Int in
            nextID += 1
            return nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                var waiters: [CheckedContinuation<Void, Never>] = []
                let alreadyCancelled = lock.withLock { () -> Bool in
                    sleeps.append(duration)
                    let count = sleeps.count
                    waiters = sleepWaiters.filter { $0.count <= count }.map(\.continuation)
                    sleepWaiters.removeAll { $0.count <= count }
                    if cancelledIDs.contains(id) { return true }
                    sleepers.append(Sleeper(id: id, deadline: elapsed + duration, continuation: continuation))
                    return false
                }
                waiters.forEach { $0.resume() }
                if alreadyCancelled { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let sleeper = lock.withLock { () -> Sleeper? in
                cancelledIDs.insert(id)
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        let due = lock.withLock { () -> [Sleeper] in
            elapsed += duration
            let due = sleepers.filter { $0.deadline <= elapsed }
            sleepers.removeAll { $0.deadline <= elapsed }
            return due
        }
        due.forEach { $0.continuation.resume() }
    }

    /// Suspends until `sleep` has been called `count` times in total —
    /// event-driven, like `ViewportVenueService.waitForRequests`.
    func waitForSleeps(_ count: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready = lock.withLock { () -> Bool in
                if sleeps.count >= count { return true }
                sleepWaiters.append((count, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }
}

/// Records every viewport query in order and answers each one only when
/// the test says so. Deliberately ignores task cancellation: a cancelled
/// fetch can still be answered late, which is exactly the stale response
/// the model's token has to drop.
private actor ViewportVenueService: VenueListing {
    enum Outcome: Sendable {
        case success([Venue])
        case failure
    }
    private enum TestError: Error { case failed }

    private var queries: [VenueQuery] = []
    private var pending: [Int: CheckedContinuation<Outcome, Never>] = [:]
    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    var requestCount: Int { queries.count }

    func query(ofRequest number: Int) -> VenueQuery? {
        queries.indices.contains(number - 1) ? queries[number - 1] : nil
    }

    func fetchVenues(_ query: VenueQuery) async throws -> [Venue] {
        queries.append(query)
        let number = queries.count
        let ready = requestWaiters.filter { $0.count <= number }
        requestWaiters.removeAll { $0.count <= number }
        ready.forEach { $0.continuation.resume() }
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
            pending[number] = continuation
        }
        switch outcome {
        case .success(let venues): return venues
        case .failure: throw TestError.failed
        }
    }

    /// Suspends until `count` requests have been made in total. Never times
    /// out (see `ControlledVenueService` in `VenuesModelTests` for why).
    func waitForRequests(_ count: Int) async throws {
        guard queries.count < count else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            requestWaiters.append((count, continuation))
        }
    }

    func respond(toRequest number: Int, with outcome: Outcome) {
        pending.removeValue(forKey: number)?.resume(returning: outcome)
    }
}
