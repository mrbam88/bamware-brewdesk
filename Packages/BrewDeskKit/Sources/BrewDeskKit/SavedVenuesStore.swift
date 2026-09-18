import Foundation
import Observation
import VenueKit

@MainActor
public protocol SavedVenuePersisting: AnyObject {
    func loadVenueIDs() -> [String]
    func saveVenueIDs(_ venueIDs: [String])
}

/// What the Saved tab's one-line status shows (bamware-brewdesk#175).
/// `.localOnly` covers both "signed out" and "signed in but not yet/
/// currently synced" — the tab makes no distinction, no prompts either way.
public enum SavedVenuesSyncStatus: Equatable, Sendable {
    case localOnly
    case synced
}

/// Optional second conformance for a `SavedVenuePersisting` that also syncs
/// to a server (`ServerSavedVenuePersistence`). `SavedVenuesStore.syncStatus`
/// below reads this via a cast so the store itself stays sync-agnostic —
/// plain local-only persistence (`UserDefaultsSavedVenuePersistence`) simply
/// doesn't conform, and the store reports `.localOnly` for it.
@MainActor
public protocol SavedVenuesSyncStatusReporting: AnyObject {
    var syncStatus: SavedVenuesSyncStatus { get }
}

@MainActor
public final class UserDefaultsSavedVenuePersistence: SavedVenuePersisting {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "brewdesk.saved-venue-ids"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func loadVenueIDs() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    public func saveVenueIDs(_ venueIDs: [String]) {
        defaults.set(venueIDs, forKey: key)
    }
}

@MainActor
@Observable
public final class SavedVenuesStore {
    public private(set) var venueIDs: [String]

    @ObservationIgnored
    private let persistence: any SavedVenuePersisting

    public init(persistence: any SavedVenuePersisting = UserDefaultsSavedVenuePersistence()) {
        self.persistence = persistence
        self.venueIDs = persistence.loadVenueIDs()
    }

    public func contains(_ venueID: String) -> Bool {
        venueIDs.contains(venueID)
    }

    public func toggle(_ venueID: String) {
        if let index = venueIDs.firstIndex(of: venueID) {
            venueIDs.remove(at: index)
        } else {
            venueIDs.insert(venueID, at: 0)
        }
        persistence.saveVenueIDs(venueIDs)
    }

    /// Re-reads `venueIDs` from the underlying persistence without going
    /// through `toggle`. Needed because `ServerSavedVenuePersistence`'s
    /// sign-in merge writes straight to the wrapped local store (async, off
    /// the store's own `venueIDs` mutation path) — the composition root
    /// calls this afterward so the `@Observable` `venueIDs` UI depends on
    /// picks up the merged set.
    public func reload() {
        venueIDs = persistence.loadVenueIDs()
    }

    /// The Saved tab's one-line status (bamware-brewdesk#175) — `.localOnly`
    /// for plain local persistence and for a `ServerSavedVenuePersistence`
    /// that hasn't (yet) synced; `.synced` once it has.
    public var syncStatus: SavedVenuesSyncStatus {
        (persistence as? any SavedVenuesSyncStatusReporting)?.syncStatus ?? .localOnly
    }
}

@MainActor
@Observable
public final class SavedVenuesModel {
    public enum Phase: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var venues: [Venue] = []
    /// Saved IDs that failed to hydrate on the last load. Non-zero with
    /// `.loaded` means "partial" — the screen shows what it has plus a banner,
    /// instead of silently dropping cafés the user saved.
    public private(set) var failedCount = 0

    @ObservationIgnored
    private let service: any VenueDetailServing

    public init(service: any VenueDetailServing) {
        self.service = service
    }

    public func load(venueIDs: [String]) async {
        guard !venueIDs.isEmpty else {
            venues = []
            failedCount = 0
            phase = .loaded
            return
        }

        phase = .loading
        var loaded: [Venue] = []
        var failures = 0
        var lastError: (any Error)?
        // Serial keeps persisted order; one bad ID must not hide the rest.
        for venueID in venueIDs {
            if Task.isCancelled { return }
            do {
                loaded.append(try await service.fetchVenue(id: venueID))
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                failures += 1
                lastError = error
            }
        }
        venues = loaded
        failedCount = failures
        if loaded.isEmpty, let lastError {
            phase = .failed(lastError.localizedDescription)
        } else {
            phase = .loaded
        }
    }
}
