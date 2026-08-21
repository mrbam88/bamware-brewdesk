import Foundation
import Observation
import VenueKit

@MainActor
public protocol SavedVenuePersisting: AnyObject {
    func loadVenueIDs() -> [String]
    func saveVenueIDs(_ venueIDs: [String])
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
