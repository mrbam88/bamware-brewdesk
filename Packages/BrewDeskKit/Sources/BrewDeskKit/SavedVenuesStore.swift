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

    @ObservationIgnored
    private let service: any VenueDetailServing

    public init(service: any VenueDetailServing) {
        self.service = service
    }

    public func load(venueIDs: [String]) async {
        guard !venueIDs.isEmpty else {
            venues = []
            phase = .loaded
            return
        }

        phase = .loading
        var loaded: [Venue] = []
        do {
            for venueID in venueIDs {
                try Task.checkCancellation()
                loaded.append(try await service.fetchVenue(id: venueID))
            }
            venues = loaded
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            venues = loaded
            phase = loaded.isEmpty ? .failed(error.localizedDescription) : .loaded
        }
    }
}
