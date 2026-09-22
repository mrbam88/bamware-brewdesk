import Foundation
import Observation
import VenueKit

public struct VenueLoadRequest: Equatable, Sendable {
    let query: VenueQuery
    let revision: Int
}

/// Single source of truth for the venue list + filters.
/// @MainActor + @Observable: Swift 6-clean, SwiftUI-native observation.
/// DI-framework-agnostic — the app's composition root injects the API.
@MainActor
@Observable
public final class VenuesModel {
    public enum Phase: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    public private(set) var phase: Phase = .idle

    /// Everything the engine answered for the current request (or the cold-
    /// start snapshot). Category filters never touch the wire — they derive
    /// `venues` from this list locally (brewdesk#77).
    private var loadedVenues: [Venue] = []

    /// What the UI shows: the loaded list with the active filters and search
    /// applied. Inclusive filter semantics live in `VenueFilter` (brewdesk#77);
    /// debounced type-to-search matching lives in `VenueSearch` (brewdesk#78).
    /// Ordering last: `VenueOrdering` stably partitions observed venues
    /// before unobserved ones, so a search's match rank still wins inside
    /// each group (brewdesk#159).
    public var venues: [Venue] {
        guard !activeSearchText.isEmpty else {
            return VenueOrdering.observedFirst(localMatches)
        }
        // bd#200: a settled, non-empty search widens beyond `localMatches`
        // with whatever the citywide server search (`scheduleServerSearch`)
        // found that the current viewport never loaded. When the server
        // hasn't answered yet, or answered with nothing new (every scenario
        // before bd#200, including every existing fixture), this is a no-op
        // and `venues` behaves exactly as it always has.
        let matches = localMatches
        let serverOnly = filter.apply(to: matchingServerResults)
            .filter { server in !matches.contains { $0.id == server.id } }
        guard !serverOnly.isEmpty else {
            return VenueOrdering.observedFirst(matches)
        }
        let merged = VenueSearch.mergeCityWide(
            query: activeSearchText, local: matches, serverOnly: serverOnly,
            centerLat: centerLat, centerLng: centerLng
        )
        return VenueOrdering.observedFirst(merged)
    }

    /// The loaded viewport list with filters + the instant local search
    /// applied — everything `venues` used to be before bd#200 added the
    /// citywide server widening above.
    private var localMatches: [Venue] {
        VenueSearch.apply(activeSearchText, to: filter.apply(to: loadedVenues))
    }

    /// `serverSearchResults`, but only while it actually answers the
    /// CURRENT settled search — a citywide result for a superseded query
    /// must never leak into `venues` for the query that replaced it. The
    /// in-flight fetch itself already ignores stale answers by revision
    /// (`scheduleServerSearch`); this is the second, independent guard at
    /// the read site.
    private var matchingServerResults: [Venue] {
        serverSearchResultsText == activeSearchText ? serverSearchResults : []
    }

    private var filter: VenueFilter {
        VenueFilter(
            laptopFriendlyOnly: laptopFriendlyOnly,
            minWifi: minWifi,
            minOutlets: minOutlets,
            minSeating: minSeating,
            venueType: venueType
        )
    }

    // MARK: - Honest filter sections (brewdesk#222)

    /// True while any of the four filter-menu dimensions constrain the
    /// list — the same set `WorkFitFilterMenu.activeFilterCount` badges.
    /// `venueType` is deliberately excluded: it has no "unknown" outcome of
    /// its own (see `VenueFilter.classify`), so it never produces an
    /// `unknownVenues` entry and doesn't change whether the shelf/map show
    /// the confirmed/unknown split.
    public var hasActiveFilter: Bool {
        laptopFriendlyOnly || minWifi != nil || minOutlets != nil || minSeating != nil
    }

    /// `venues`, split by `VenueFilter.classify`: every constrained
    /// attribute is known and passes. Order is a stable filter over
    /// `venues`' own order — observed-first/score/search-rank, then (while
    /// no venue type is explicitly chosen) cafés before other types — so
    /// nothing about that composition changes here, only which half of it a
    /// given venue lands in.
    public var confirmedVenues: [Venue] {
        VenueOrdering.cafeDefaultFirst(
            venues.filter { filter.classify($0) == .confirmed },
            venueTypeChosen: venueType != nil
        )
    }

    /// `venues`' complementary half: nothing constrained is known to FAIL
    /// the active filter, but at least one constrained attribute is
    /// unknown (e.g. WeWork's Wi-Fi under a "fast Wi-Fi" filter — TestFlight
    /// build 28). Always empty while `hasActiveFilter` is false — `classify`
    /// never returns `.unknown` with no active constraint.
    public var unknownVenues: [Venue] {
        VenueOrdering.cafeDefaultFirst(
            venues.filter { filter.classify($0) == .unknown },
            venueTypeChosen: venueType != nil
        )
    }

    public var confirmedCount: Int { confirmedVenues.count }
    public var unknownCount: Int { unknownVenues.count }

    /// True while `venues` is the bundled snapshot rather than an engine
    /// response (brewdesk#28). Cleared by the first successful load.
    public private(set) var isShowingSnapshot = false

    /// What the snapshot banner should say, or nil when the rows on screen
    /// came from the engine.
    public enum SnapshotBannerState: Equatable, Sendable { case loading, offline }
    public var snapshotBanner: SnapshotBannerState? {
        guard isShowingSnapshot else { return nil }
        if case .failed = phase { return .offline }
        return .loading
    }

    // Filters — applied locally to the loaded list; mutating them re-queries
    // nothing (brewdesk#77).
    public var laptopFriendlyOnly = false
    public var minWifi: WifiMinimum?
    public var minOutlets: OutletMinimum?
    public var minSeating: SeatingMinimum?
    public var venueType: VenueTypeFilter?

    /// Show venueType chips only when the dataset actually has more than one
    /// type (or a type filter is active) — all-cafe data keeps the UI as-is.
    public var venueTypesAvailable: Bool {
        venueType != nil || Set(loadedVenues.compactMap(\.venueType)).count > 1
    }
    /// Bound to the search fields. Typing filters the loaded list ~200ms
    /// after the last keystroke (brewdesk#78) — no submit, no network.
    public var searchQuery = "" {
        didSet { scheduleSearchApplication() }
    }
    /// The text `venues` is currently narrowed by; trails `searchQuery` by
    /// the debounce, except submit/clear which apply immediately.
    private var activeSearchText = "" {
        didSet { scheduleServerSearch() }
    }
    /// Internal (not `private`) so `@testable` tests can `await` it directly
    /// instead of guessing a real-time margin for the ~200ms debounce. A
    /// fixed `Task.sleep` in the test (the pre-fix `waitForDebounce()`)
    /// raced the growing BrewDeskKit-Package suite's parallel test load in
    /// CI: `SearchAsYouTypeTests` reported `venues` as still the full,
    /// unnarrowed list even though this model had already applied the
    /// search correctly — the scheduler simply hadn't resumed the debounce
    /// Task within the test's fixed wait under contention. Awaiting the
    /// real Task's completion removes the race entirely; it was never a
    /// product regression in local search narrowing.
    @ObservationIgnored
    var searchDebounceTask: Task<Void, Never>?
    private var requestRevision = 0

    // MARK: - Citywide server search (bd#200)
    //
    // Root cause: `venues` used to be a purely LOCAL filter over whatever
    // pins the current viewport happened to have loaded (≤500 within ≤3km)
    // — a café outside that viewport could never be found by typing its
    // name, however exact the match, because search never touched the
    // wire. This runs a SEPARATE, debounced `q=<text>` request over a
    // citywide radius alongside the existing instant local filter; results
    // are unioned into `venues` above. `request`/`load` (the viewport
    // fetch) are untouched — `searchNeverReachesTheQuery` still holds.

    /// bd#200: NYC-wide radius the server search asks over, independent of
    /// whatever viewport radius `request` is currently using — a citywide
    /// search must find a match anywhere in the five boroughs, not just
    /// near the map's current center. Server cap is 50,000m
    /// (bamware-venue-engine `schema.ts`); this stays comfortably under it.
    public static let serverSearchRadiusM = 40_000
    /// bd#200: a citywide search only needs enough rows to fill the shelf
    /// list, not the map's full 500-pin viewport budget.
    public static let serverSearchLimit = 50
    /// bd#200: below this length a server round trip isn't worth spending —
    /// matches the ticket's "≥ 2 characters" trigger.
    public static let serverSearchMinimumLength = 2

    private var serverSearchResults: [Venue] = []
    /// The exact settled text `serverSearchResults` answers — compared
    /// against `activeSearchText` at the read site (`matchingServerResults`)
    /// so a stale answer can never leak into a later query's results.
    private var serverSearchResultsText = ""
    /// True while the citywide request is in flight — drives the search
    /// field's inline progress indicator and the shelf's "Searching all of
    /// NYC…" state.
    public private(set) var isSearchingServer = false
    /// True when the last citywide request failed (network/HTTP) — drives
    /// the quiet "Couldn't search beyond this area" line. Local results (if
    /// any) are untouched; this is purely advisory, never an alert.
    public private(set) var serverSearchFailed = false
    /// Internal (not `private`) for the same reason as `searchDebounceTask`
    /// above — lets tests await the settled citywide request deterministically.
    @ObservationIgnored
    var serverSearchTask: Task<Void, Never>?
    @ObservationIgnored
    private var serverSearchRevision = 0

    /// The text `venues` is currently searching city-wide for — exposed
    /// read-only so views can show search-specific copy ("No cafés named
    /// “<text>”…") without reaching into `activeSearchText` itself.
    public var settledSearchText: String { activeSearchText }

    /// bd#200: true only while there's genuinely nothing to show yet FOR
    /// THIS SEARCH — the local list is empty and the citywide answer hasn't
    /// landed. Drives the shelf's "Searching all of NYC…" state instead of
    /// flashing the generic empty state for the ~200ms-plus a real request
    /// takes.
    public var isCityWideSearchPending: Bool {
        !activeSearchText.isEmpty && isSearchingServer && localMatches.isEmpty
    }

    /// Cancels any in-flight citywide request and, for a settled query at
    /// least `serverSearchMinimumLength` long, schedules a new one. Cleared
    /// (no request, no stale results, no progress/failure flags) for
    /// anything shorter, including the empty string a clear applies
    /// immediately — matches "clearing restores the previous viewport's
    /// venue set" with no lingering citywide state.
    private func scheduleServerSearch() {
        serverSearchTask?.cancel()
        let text = activeSearchText
        guard text.count >= Self.serverSearchMinimumLength else {
            serverSearchResults = []
            serverSearchResultsText = ""
            isSearchingServer = false
            serverSearchFailed = false
            return
        }
        serverSearchRevision &+= 1
        let revision = serverSearchRevision
        isSearchingServer = true
        serverSearchFailed = false
        let query = VenueQuery(
            lat: Self.coverageCenterLat,
            lng: Self.coverageCenterLng,
            radiusM: Self.serverSearchRadiusM,
            search: text,
            sort: .workScore,
            limit: Self.serverSearchLimit
        )
        serverSearchTask = Task { [weak self, api] in
            do {
                let result = try await api.fetchVenuesResult(query)
                try Task.checkCancellation()
                guard let self, self.serverSearchRevision == revision else { return }
                self.serverSearchResults = result.venues
                self.serverSearchResultsText = text
                self.isSearchingServer = false
            } catch is CancellationError {
                // Superseded by a newer query — its own task owns the
                // outcome; nothing to update here.
            } catch {
                guard let self, self.serverSearchRevision == revision else { return }
                self.isSearchingServer = false
                self.serverSearchFailed = true
            }
        }
    }

    /// bd#198 root cause: `VenuesModel` used to have no memory of WHY
    /// `centerLat/Lng` last changed, so a passive GPS tick
    /// (`updateCenterIfNeeded`, DiscoveryRootView's location-driven path)
    /// could silently overwrite a centre the user had just explored via
    /// "Search this area" or a pan — every later GPS tick did the same,
    /// snapping the map straight back to the phone's location. This is now
    /// the single source of truth for whether the current centre is one the
    /// user explicitly chose.
    public enum CenterSource: Equatable, Sendable {
        /// The Union Square fallback, or "Browse NYC" — never overwritten by
        /// a passive GPS tick once set (see `browseCoverageCenter`).
        case coverageDefault
        /// Set by a real location fix — either the cold-start correction or
        /// an explicit locate-me tap (`centerOnUser`).
        case userLocation
        /// Set by `updateViewport` — "Search this area" or any other
        /// viewport-driven refetch. A passive GPS tick never overwrites this.
        case exploredViewport
    }
    public private(set) var centerSource: CenterSource = .coverageDefault
    /// True while passive GPS updates (`updateCenterIfNeeded`) are still
    /// allowed to move the centre — armed by the cold-start first fix and by
    /// `centerOnUser` (locate-me), disarmed by `updateViewport` and
    /// `browseCoverageCenter` (bd#198). Distinct from `centerSource` so a
    /// caller can tell "we're centered on the user" (`centerSource ==
    /// .userLocation`) apart from "…and we're still tracking them"
    /// (`followsUser`) — locate-me sets both; a stale `.userLocation` centre
    /// the user has since panned away from should set neither.
    public private(set) var followsUser = false
    /// Cold start ends the moment the first real fix is offered to
    /// `updateCenterIfNeeded` — before that, ANY fix (however far from the
    /// current fallback) replaces it unconditionally. Kept `true` by
    /// `browseCoverageCenter` even on a model that never received a real fix
    /// yet, so "Browse NYC" is sticky against a stale/delayed GPS answer
    /// landing right after (bd#198 — the user explicitly asked to look at
    /// NYC, not wherever they physically are).
    @ObservationIgnored
    private var hasAppliedFirstFix = false
    /// Passive GPS ticks below this distance from the current centre never
    /// refetch even while following (bd#198) — otherwise ordinary walking
    /// jitter would re-trigger `DiscoveryRootView`'s request on every fix.
    public static let followDistanceThresholdM = 150.0

    /// Deterministic fallback until Core Location supplies a coordinate.
    public private(set) var centerLat = VenuesModel.coverageCenterLat
    public private(set) var centerLng = VenuesModel.coverageCenterLng
    /// bd#192 ("Search this area"): the radius actually driving the last
    /// dispatched query — starts at `defaultRadiusM` and only ever changes
    /// through `updateViewport(lat:lng:radiusM:)`, the same viewport-driven
    /// path the map's pill and the locate-me refetch both use.
    public private(set) var radiusM = VenuesModel.defaultRadiusM

    /// bd#192: fixed radius before any real viewport has been observed —
    /// the pre-#192 constant, now just the starting point instead of the
    /// permanent value.
    public static let defaultRadiusM = 2_500
    /// bd#192: viewport-derived radius bounds. A citywide zoom-out never
    /// asks the engine for an unbounded radius; a tight zoom-in never asks
    /// for less than a still-useful neighborhood radius.
    public static let minRadiusM = 300
    public static let maxRadiusM = 3_000
    /// bd#192 root cause: a fixed `limit: 100` on a 2.5 km query silently
    /// dropped every hollow/unrated pin past the top 100 by work score once
    /// a viewport held 1,000+ venues (Manhattan does today). Raised here;
    /// the live engine's documented cap is 200 as of this ticket
    /// (bamware-venue-engine `schema.ts`), with a companion server ticket
    /// (ve#140) raising it to 500 the same day — `VenueAPI` requests this
    /// higher value and falls back to a safe one if the server hasn't
    /// deployed the raised cap yet (see `VenueAPI.fetchVenuesResult`).
    public static let viewportQueryLimit = 500

    /// What the engine reported for the last successfully loaded viewport
    /// (ve#46, bd#108) — drives the coverage banner. `.researched` until the
    /// first load answers, and whenever the engine hasn't shipped the field
    /// yet (`VenueLoadResult`'s default), so a pre-ve#46 build shows no
    /// banner, exactly like today.
    public private(set) var coverage: CoverageLevel = .researched

    // NYC anchor (Union Square) — the deterministic default center before a
    // real location is known, and where "Browse NYC" snaps back to. bd#108
    // removed the client-side rejection that used to keep every out-of-NYC
    // coordinate pinned here: the model now always queries the real
    // viewport it was given (brewdesk#1 fallback removed).
    nonisolated static let coverageCenterLat = 40.7359
    nonisolated static let coverageCenterLng = -73.9911

    @ObservationIgnored
    private let api: any VenueListing
    @ObservationIgnored
    private var loadGeneration = 0
    /// Bundled first-paint venues (`VenueSnapshot.load()`); empty when none ship.
    @ObservationIgnored
    private let snapshot: [Venue]
    @ObservationIgnored
    private var hasReceivedLiveVenues = false

    public init(api: any VenueListing, snapshot: [Venue] = []) {
        self.api = api
        self.snapshot = snapshot
    }

    public var request: VenueLoadRequest {
        VenueLoadRequest(
            // Category filters and search are deliberately absent: the
            // engine's wire predicate fails unknown values (store.ts), which
            // emptied the list — filtering (brewdesk#77) and search
            // (brewdesk#78) are local over the loaded list.
            query: VenueQuery(
                lat: centerLat,
                lng: centerLng,
                radiusM: radiusM,
                // Decision (bd#192): kept at the server default rather than
                // switching to `.distance` for the map fetch. The
                // companion server ticket (ve#140) commits `sort=work_score`
                // to returning evidence-backed pins first, then hollow pins
                // ordered by ascending distance — the same completeness a
                // client-side distance sort would buy, without a second
                // local re-sort for the shelf or risking the tested
                // observed-first/search-match-rank composition order
                // (`VenueOrdering`, `VenueOrderingTests`) that both the
                // shelf and the map share via `venues` below.
                sort: .workScore,
                limit: Self.viewportQueryLimit
            ),
            revision: requestRevision
        )
    }

    /// The passive, location-driven path — `DiscoveryRootView`'s
    /// `.task(id: request)`/`.onChange(of: locationService.location)` call
    /// this on every fix. bd#198: unlike `centerOnUser` (an explicit locate-
    /// me tap), a fix here only moves the centre while that's still safe —
    /// the cold-start correction (no fix has ever landed) or, afterward,
    /// only while `centerSource == .userLocation && followsUser` (bd#198;
    /// `updateViewport`/`browseCoverageCenter` clear `followsUser`, so an
    /// explored viewport or "Browse NYC" is never overwritten by a later
    /// tick). Also `false` — a no-op — for a move under
    /// `followDistanceThresholdM` while following, so ordinary walking
    /// jitter doesn't refetch on every fix. Always accepts a real coordinate
    /// once it's allowed to apply at all — bd#108 removed the
    /// >50km-from-NYC rejection this used to apply.
    @discardableResult
    public func updateCenterIfNeeded(lat: Double, lng: Double) -> Bool {
        guard !hasAppliedFirstFix || (centerSource == .userLocation && followsUser) else { return false }
        let isFirstFix = !hasAppliedFirstFix
        hasAppliedFirstFix = true
        if isFirstFix {
            // The cold-start correction always arms following, even on the
            // near-impossible coincidence that the first real fix lands
            // exactly on the Union Square fallback — this doesn't depend on
            // the coordinate actually moving (mirrors `centerOnUser`, which
            // re-arms following the same way on an explicit locate-me tap).
            centerSource = .userLocation
            followsUser = true
        } else {
            guard Self.metersBetween(centerLat, centerLng, lat, lng) >= Self.followDistanceThresholdM else {
                return false
            }
        }
        guard centerLat != lat || centerLng != lng else { return false }
        centerLat = lat
        centerLng = lng
        centerSource = .userLocation
        followsUser = true
        return true
    }

    /// "Browse NYC": snap back to the coverage anchor and re-query. Now a
    /// manual affordance only (the empty/"no cafes" states offer it) — it no
    /// longer fires automatically for a coordinate far from NYC. bd#198:
    /// also stops following GPS — the user asked to look at NYC, not
    /// wherever they physically are — and is sticky against a fix landing
    /// right after even on a model that has never seen a real fix yet
    /// (`hasAppliedFirstFix = true` closes the cold-start exception).
    public func browseCoverageCenter() {
        centerLat = Self.coverageCenterLat
        centerLng = Self.coverageCenterLng
        radiusM = Self.defaultRadiusM
        centerSource = .coverageDefault
        followsUser = false
        hasAppliedFirstFix = true
        requestRevision &+= 1
    }

    /// bd#192 ("Search this area") + a manual pan that triggers a refetch:
    /// the viewport-driven fetch path — unlike `updateCenterIfNeeded`
    /// (passive, location-driven recenter only), this also carries the
    /// radius the current map viewport implies, clamped to
    /// `minRadiusM...maxRadiusM`. Same "already here" no-op contract:
    /// returns `false` (and touches nothing, including `centerSource`) when
    /// neither the center nor the radius actually changed, so a caller can
    /// safely call this on every settle without spamming no-op requests.
    /// bd#198: marks the new centre `.exploredViewport` and stops following
    /// GPS — a later passive `updateCenterIfNeeded` tick must never
    /// overwrite a viewport the user just explored (the root cause of
    /// "Search this area" snapping back to the phone's location).
    @discardableResult
    public func updateViewport(lat: Double, lng: Double, radiusM: Int) -> Bool {
        let clampedRadius = min(max(radiusM, Self.minRadiusM), Self.maxRadiusM)
        guard centerLat != lat || centerLng != lng || self.radiusM != clampedRadius else { return false }
        centerLat = lat
        centerLng = lng
        self.radiusM = clampedRadius
        centerSource = .exploredViewport
        followsUser = false
        return true
    }

    /// bd#198: the locate-me button's explicit "recenter on me and keep
    /// following" — distinct from `updateViewport` (which would mark the
    /// result `.exploredViewport` and stop following) even though both
    /// carry a lat/lng/radius. Always (re)arms `followsUser = true` and
    /// `centerSource = .userLocation`, even when the coordinate itself
    /// didn't change (the map might already be centered on the user, but a
    /// tap is still an explicit request to resume following their GPS).
    @discardableResult
    public func centerOnUser(lat: Double, lng: Double, radiusM: Int) -> Bool {
        let clampedRadius = min(max(radiusM, Self.minRadiusM), Self.maxRadiusM)
        let changed = centerLat != lat || centerLng != lng || self.radiusM != clampedRadius
        centerLat = lat
        centerLng = lng
        self.radiusM = clampedRadius
        centerSource = .userLocation
        followsUser = true
        hasAppliedFirstFix = true
        return changed
    }

    /// bd#210: `updateCenterIfNeeded` (the passive, location-driven path
    /// `DiscoveryRootView`'s `.task(id: request)` calls on every fix) only
    /// ever carries lat/lng — it never had a radius to update, so the very
    /// first fetch after a real GPS fix kept querying at `defaultRadiusM`
    /// (2,500m) while bd#209's walking-scale initial camera (~0.014° span)
    /// implies a radius under a third of that. The mismatch alone — not any
    /// real user pan — made `CafeMapScreen.needsSearchAreaPill` see a >2×
    /// radius "change" on cold start and show the pill with zero gestures.
    /// `CafeMapScreen.applyCenterChange()` calls this right after computing
    /// the region the camera will actually show, so by the time
    /// `visibleRegion` settles to match, `radiusM` already does too.
    /// Deliberately NOT `centerOnUser`/`updateViewport` — both would touch
    /// `centerSource`/`followsUser`, which `updateCenterIfNeeded` already
    /// set correctly; this only ever corrects the radius.
    @discardableResult
    public func syncRadiusToCamera(_ radiusM: Int) -> Bool {
        let clampedRadius = min(max(radiusM, Self.minRadiusM), Self.maxRadiusM)
        guard self.radiusM != clampedRadius else { return false }
        self.radiusM = clampedRadius
        return true
    }

    nonisolated static func metersBetween(
        _ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double
    ) -> Double {
        let earthRadiusM = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLng / 2) * sin(dLng / 2)
        return earthRadiusM * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Dataset-level stats for the stat strip; nil (strip hidden) on failure.
    public private(set) var health: HealthResponse?

    public func loadHealth() async {
        health = (try? await api.fetchHealth()).flatMap { $0 }
    }

    /// Idempotent entry point for views that merely need the stats present:
    /// fetches once, refetches only after a failure left `health` nil.
    public func loadHealthIfNeeded() async {
        guard health == nil else { return }
        await loadHealth()
    }

    /// Debounce (~200ms): one application per pause in typing, so the list
    /// doesn't reshuffle on every keystroke. Clearing applies immediately —
    /// tapping ✕ must feel instant.
    private func scheduleSearchApplication() {
        searchDebounceTask?.cancel()
        let target = VenueSearch.normalize(searchQuery)
        guard target != activeSearchText else { return }
        guard !target.isEmpty else {
            activeSearchText = ""
            return
        }
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, !Task.isCancelled else { return }
            self.activeSearchText = target
        }
    }

    /// Keyboard Search key: skip the debounce and apply now.
    public func submitSearch() {
        searchDebounceTask?.cancel()
        activeSearchText = VenueSearch.normalize(searchQuery)
    }

    public func clearSearch() {
        searchQuery = ""    // didSet applies the empty query immediately
    }

    public func retry() {
        requestRevision &+= 1
    }

    public func cycleWifiMinimum() {
        switch minWifi {
        case nil: minWifi = .ok
        case .some(.ok): minWifi = .fast
        default: minWifi = nil
        }
    }

    public func cycleOutletMinimum() {
        switch minOutlets {
        case nil: minOutlets = .some
        case .some(.some): minOutlets = .plenty
        default: minOutlets = nil
        }
    }

    public func cycleSeatingMinimum() {
        switch minSeating {
        case nil: minSeating = .some
        case .some(.some): minSeating = .plenty
        default: minSeating = nil
        }
    }

    /// bd#223: resolves a café by id for a tapped "Recent" row whose venue
    /// isn't currently in `venues` (it scrolled out of the loaded viewport
    /// since it was recorded). Checks memory first — free, and covers the
    /// common case (the recent is still on screen or was just selected) —
    /// then falls back to the same detail endpoint `SavedVenuesModel`/
    /// `SavedVenuesStore` already use for a saved café. `api` doesn't
    /// declare `VenueDetailServing` itself (this model's only documented
    /// contract is `VenueListing`, so tests can inject a listing-only
    /// double) — every real conformer (`VenueAPI`, `ScenarioVenueService`)
    /// happens to also implement it, so the cast only ever fails for a
    /// deliberately listing-only test double, in which case this correctly
    /// reports "can't resolve" rather than crashing.
    public func venue(id: String) async throws -> Venue {
        if let cached = loadedVenues.first(where: { $0.id == id }) { return cached }
        guard let detailService = api as? any VenueDetailServing else {
            throw VenueAPIError.invalidResponse
        }
        return try await detailService.fetchVenue(id: id)
    }

    public func load(_ request: VenueLoadRequest) async {
        loadGeneration += 1
        let generation = loadGeneration
        phase = .loading
        // Cold start: until the engine has answered once, paint the bundled
        // snapshot instead of a spinner. Never re-seed after a live answer —
        // an empty filter result must stay empty, not flash the snapshot.
        if !hasReceivedLiveVenues, loadedVenues.isEmpty, !snapshot.isEmpty {
            loadedVenues = snapshot
            isShowingSnapshot = true
        }
        do {
            let answer = try await api.fetchVenuesResult(request.query)
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }
            loadedVenues = answer.venues
            coverage = answer.coverage
            hasReceivedLiveVenues = true
            isShowingSnapshot = false
            phase = .loaded
        } catch is CancellationError {
            guard generation == loadGeneration else { return }
            phase = (loadedVenues.isEmpty || isShowingSnapshot) ? .idle : .loaded
            return
        } catch {
            guard generation == loadGeneration else { return }
            phase = .failed(error.localizedDescription)
        }
    }

}
