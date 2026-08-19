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
    public private(set) var venues: [Venue] = []

    // Filters — mutating them and calling load() re-queries the engine.
    public var laptopFriendlyOnly = false
    public var minWifi: WifiMinimum?
    public var minOutlets: OutletMinimum?
    public var searchQuery = ""
    private var submittedSearchQuery: String?
    private var requestRevision = 0

    /// Deterministic fallback until Core Location supplies a coordinate.
    public private(set) var centerLat = 40.7359
    public private(set) var centerLng = -73.9911
    public let radiusM = 2500

    @ObservationIgnored
    private let api: any VenueListing
    @ObservationIgnored
    private var loadGeneration = 0

    public init(api: any VenueListing) {
        self.api = api
    }

    public var request: VenueLoadRequest {
        VenueLoadRequest(
            query: VenueQuery(
                lat: centerLat,
                lng: centerLng,
                radiusM: radiusM,
                wifiMinimum: minWifi,
                outletMinimum: minOutlets,
                laptopFriendlyOnly: laptopFriendlyOnly,
                search: submittedSearchQuery,
                sort: .workScore,
                limit: 100
            ),
            revision: requestRevision
        )
    }

    @discardableResult
    public func updateCenterIfNeeded(lat: Double, lng: Double) -> Bool {
        guard centerLat != lat || centerLng != lng else { return false }
        centerLat = lat
        centerLng = lng
        return true
    }

    public func submitSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        submittedSearchQuery = query.isEmpty ? nil : query
    }

    public func clearSearch() {
        searchQuery = ""
        submittedSearchQuery = nil
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

    public func load(_ request: VenueLoadRequest) async {
        loadGeneration += 1
        let generation = loadGeneration
        phase = .loading
        do {
            let loadedVenues = try await api.fetchVenues(request.query)
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }
            venues = loadedVenues
            phase = .loaded
        } catch is CancellationError {
            guard generation == loadGeneration else { return }
            phase = venues.isEmpty ? .idle : .loaded
            return
        } catch {
            guard generation == loadGeneration else { return }
            phase = .failed(error.localizedDescription)
        }
    }

}
