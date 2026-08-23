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
    public var venues: [Venue] {
        VenueSearch.apply(activeSearchText, to: filter.apply(to: loadedVenues))
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
    private var activeSearchText = ""
    @ObservationIgnored
    private var searchDebounceTask: Task<Void, Never>?
    private var requestRevision = 0

    /// Deterministic fallback until Core Location supplies a coordinate.
    public private(set) var centerLat = VenuesModel.coverageCenterLat
    public private(set) var centerLng = VenuesModel.coverageCenterLng
    public let radiusM = 2500

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
                sort: .workScore,
                limit: 100
            ),
            revision: requestRevision
        )
    }

    /// Always accepts a real coordinate — bd#108 removed the >50km-from-NYC
    /// rejection this used to apply. `false` only means "already centered
    /// here," not "rejected."
    @discardableResult
    public func updateCenterIfNeeded(lat: Double, lng: Double) -> Bool {
        guard centerLat != lat || centerLng != lng else { return false }
        centerLat = lat
        centerLng = lng
        return true
    }

    /// "Browse NYC": snap back to the coverage anchor and re-query. Now a
    /// manual affordance only (the empty/"no cafes" states offer it) — it no
    /// longer fires automatically for a coordinate far from NYC.
    public func browseCoverageCenter() {
        centerLat = Self.coverageCenterLat
        centerLng = Self.coverageCenterLng
        requestRevision &+= 1
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
