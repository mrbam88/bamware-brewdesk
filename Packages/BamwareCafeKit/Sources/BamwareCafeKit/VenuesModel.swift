import Foundation
import Observation
import VenueKit

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

    /// Demo anchor: Union Square. Swap for CoreLocation later.
    public private(set) var centerLat = 40.7359
    public private(set) var centerLng = -73.9911
    public let radiusM = 2500

    private let api: any VenueServing
    private var loadGeneration = 0

    public init(api: any VenueServing) {
        self.api = api
    }

    public var supportsSpeedTest: Bool { api.supportsSpeedTest }

    public func updateCenter(lat: Double, lng: Double) {
        centerLat = lat
        centerLng = lng
    }

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let wifiMin = minWifi
        let laptopFriendlyOnly = laptopFriendlyOnly
        phase = .loading
        do {
            let loadedVenues = try await api.fetchVenues(
                lat: centerLat,
                lng: centerLng,
                radiusM: radiusM,
                wifiMin: wifiMin,
                outletsMin: minOutlets,
                laptopFriendly: laptopFriendlyOnly,
                neighborhood: nil,
                query: searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : searchQuery.trimmingCharacters(in: .whitespacesAndNewlines),
                sort: "work_score",
                limit: 100
            )
            guard generation == loadGeneration else { return }
            venues = loadedVenues
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Measure → submit → the engine rescores → swap the venue in place.
    public func runSpeedTest(for venue: Venue) async throws -> Venue {
        let mbps = try await api.measureDownloadMbps(samples: 3)
        let updated = try await api.submitSpeedTest(venueId: venue.id, mbpsDown: mbps)
        if let idx = venues.firstIndex(where: { $0.id == updated.id }) {
            venues[idx] = updated
        }
        return updated
    }
}
