import Foundation
import Observation
import VenueKit

public struct VenueRequest: Equatable, Sendable {
    let centerLat: Double
    let centerLng: Double
    let radiusM: Int
    let wifiMin: String?
    let outletsMin: String?
    let laptopFriendlyOnly: Bool
    let query: String?
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
    public var minWifi: String? = nil // "ok" | "fast"
    public var minOutlets: String? = nil // "some" | "plenty"
    public var searchQuery = ""
    private var submittedSearchQuery: String?
    private var requestRevision = 0

    /// Demo anchor: Union Square. Swap for CoreLocation later.
    public private(set) var centerLat = 40.7359
    public private(set) var centerLng = -73.9911
    public let radiusM = 2500

    @ObservationIgnored
    private let api: any VenueServing
    @ObservationIgnored
    private var loadGeneration = 0

    public init(api: any VenueServing) {
        self.api = api
    }

    public var supportsSpeedTest: Bool { api.supportsSpeedTest }

    public var request: VenueRequest {
        VenueRequest(
            centerLat: centerLat,
            centerLng: centerLng,
            radiusM: radiusM,
            wifiMin: minWifi,
            outletsMin: minOutlets,
            laptopFriendlyOnly: laptopFriendlyOnly,
            query: submittedSearchQuery,
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

    public func load(_ request: VenueRequest) async {
        loadGeneration += 1
        let generation = loadGeneration
        phase = .loading
        do {
            let loadedVenues = try await api.fetchVenues(
                lat: request.centerLat,
                lng: request.centerLng,
                radiusM: request.radiusM,
                wifiMin: request.wifiMin,
                outletsMin: request.outletsMin,
                laptopFriendly: request.laptopFriendlyOnly,
                neighborhood: nil,
                query: request.query,
                sort: "work_score",
                limit: 100
            )
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

    /// Measure → submit → the engine rescores → swap the venue in place.
    public func runSpeedTest(for venue: Venue) async throws -> Venue {
        let mbps = try await api.measureDownloadMbps(samples: 3)
        try Task.checkCancellation()
        let updated = try await api.submitSpeedTest(venueId: venue.id, mbpsDown: mbps)
        if let idx = venues.firstIndex(where: { $0.id == updated.id }) {
            venues[idx] = updated
        }
        return updated
    }
}
