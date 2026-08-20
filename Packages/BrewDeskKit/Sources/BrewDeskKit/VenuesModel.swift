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
    public var minSeating: SeatingMinimum?
    public var venueType: VenueTypeFilter?

    /// Show venueType chips only when the dataset actually has more than one
    /// type (or a type filter is active) — all-cafe data keeps the UI as-is.
    public var venueTypesAvailable: Bool {
        venueType != nil || Set(venues.compactMap(\.venueType)).count > 1
    }
    public var searchQuery = ""
    private var submittedSearchQuery: String?
    private var requestRevision = 0

    /// Deterministic fallback until Core Location supplies a coordinate.
    public private(set) var centerLat = VenuesModel.coverageCenterLat
    public private(set) var centerLng = VenuesModel.coverageCenterLng
    public let radiusM = 2500

    /// True when the user's real location was rejected for being outside the
    /// NYC coverage area — the UI shows coverage instead of an empty map.
    public private(set) var isOutsideCoverage = false

    // NYC coverage anchor (Union Square) and how far a coordinate may sit
    // from it before we keep showing coverage instead of following the user.
    nonisolated static let coverageCenterLat = 40.7359
    nonisolated static let coverageCenterLng = -73.9911
    nonisolated static let coverageRadiusM = 50_000.0

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
                seatingMinimum: minSeating,
                venueType: venueType,
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
        guard Self.metersFromCoverageCenter(lat: lat, lng: lng) <= Self.coverageRadiusM else {
            isOutsideCoverage = true
            return false
        }
        isOutsideCoverage = false
        guard centerLat != lat || centerLng != lng else { return false }
        centerLat = lat
        centerLng = lng
        return true
    }

    /// "Browse NYC": snap back to the coverage anchor and re-query.
    public func browseCoverageCenter() {
        centerLat = Self.coverageCenterLat
        centerLng = Self.coverageCenterLng
        requestRevision &+= 1
    }

    /// Haversine distance from the coverage anchor, in meters.
    nonisolated static func metersFromCoverageCenter(lat: Double, lng: Double) -> Double {
        let earthRadiusM = 6_371_000.0
        let dLat = (lat - coverageCenterLat) * .pi / 180
        let dLng = (lng - coverageCenterLng) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(coverageCenterLat * .pi / 180) * cos(lat * .pi / 180)
            * sin(dLng / 2) * sin(dLng / 2)
        return earthRadiusM * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Dataset-level stats for the stat strip; nil (strip hidden) on failure.
    public private(set) var health: HealthResponse?

    public func loadHealth() async {
        health = (try? await api.fetchHealth()).flatMap { $0 }
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
