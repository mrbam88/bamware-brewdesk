import Foundation

/// Deterministic stand-in for the venue engine used by UI tests and package
/// tests to pin degraded states (engine down, offline, empty, photo failures,
/// slow network). It is inert unless constructed; the app only constructs it
/// when launched with `-UITestScenario <name>` (see `UITestScenario` in the app
/// target). No network, no persistence, no UI entry point.
public struct ScenarioVenueService: VenueListing, VenueDetailServing, VenuePhotoServing, Sendable {
    public enum Scenario: String, CaseIterable, Sendable {
        /// Three fixture venues, health OK, one photo per venue whose URL is
        /// deliberately unloadable (pins thumbnail / viewer failure states).
        case fixtureOK
        /// Every call throws `VenueAPIError.http(statusCode: 500)`.
        case engineDown
        /// Every call throws `URLError(.notConnectedToInternet)`.
        case offline
        /// Venues resolve to `[]`; health OK; photos `[]`.
        case emptyVenues
        /// Venues OK; photos resolve to `[]` (engine has none).
        case photosEmpty
        /// Venues OK; photo fetch throws 500.
        case photosFail
        /// Venues resolve after a 6 s delay (cancellation-honouring); then fixtures.
        case slow
    }

    public let scenario: Scenario

    public init(scenario: Scenario) {
        self.scenario = scenario
    }

    // MARK: - Fixtures

    public static let fixtureVenues: [Venue] = [
        fixtureVenue(
            id: "fixture-roasters",
            name: "Fixture Roasters",
            lat: 40.7365, lng: -73.9905,
            neighborhood: "Union Square",
            hoursRaw: "Mon–Fri 7am–7pm · Sat–Sun 8am–6pm",
            workScore: 84,
            laptopPolicy: "unrestricted",
            venueType: "cafe"
        ),
        fixtureVenue(
            id: "fixture-library",
            name: "Fixture Reading Room",
            lat: 40.7340, lng: -73.9930,
            neighborhood: "Greenwich Village",
            hoursRaw: nil,
            workScore: 71,
            laptopPolicy: "unrestricted",
            venueType: "library"
        ),
        fixtureVenue(
            id: "fixture-corner",
            name: "Fixture Corner Cafe",
            lat: 40.7380, lng: -73.9890,
            neighborhood: "Flatiron",
            hoursRaw: "Daily 8am–5pm",
            workScore: 52,
            laptopPolicy: "discouraged",
            venueType: "cafe"
        )
    ]

    public static let fixtureHealth = HealthResponse(
        ok: true,
        venueCount: 3,
        seededAt: "2026-08-01T00:00:00Z",
        observationCount: 9
    )

    /// Port 9 (discard) is closed on every simulator; in Release the cleartext
    /// scheme is additionally blocked by ATS — either way the image load fails
    /// fast and deterministically.
    public static let fixturePhotos: [VenuePhoto] = [
        VenuePhoto(
            url: "http://127.0.0.1:9/fixture-photo-1.jpg",
            attribution: "Fixture Photographer",
            attributionUri: "https://maps.google.com/",
            widthPx: 1200,
            heightPx: 800
        )
    ]

    // MARK: - VenueListing

    public func fetchVenues(_ query: VenueQuery) async throws -> [Venue] {
        switch scenario {
        case .engineDown: throw Self.serverError
        case .offline: throw Self.offlineError
        case .emptyVenues: return []
        case .slow:
            try await Task.sleep(for: .seconds(6))
            return Self.fixtureVenues
        case .fixtureOK, .photosEmpty, .photosFail:
            return Self.fixtureVenues
        }
    }

    public func fetchHealth() async throws -> HealthResponse? {
        switch scenario {
        case .engineDown: throw Self.serverError
        case .offline: throw Self.offlineError
        default: return Self.fixtureHealth
        }
    }

    // MARK: - VenueDetailServing

    public func fetchVenue(id: String) async throws -> Venue {
        switch scenario {
        case .engineDown: throw Self.serverError
        case .offline: throw Self.offlineError
        default:
            guard let venue = Self.fixtureVenues.first(where: { $0.id == id }) else {
                throw VenueAPIError.http(statusCode: 404)
            }
            return venue
        }
    }

    // MARK: - VenuePhotoServing

    public func fetchPhotos(venueId: String) async throws -> [VenuePhoto] {
        switch scenario {
        case .engineDown, .photosFail: throw Self.serverError
        case .offline: throw Self.offlineError
        case .emptyVenues, .photosEmpty: return []
        case .fixtureOK, .slow: return Self.fixturePhotos
        }
    }

    // MARK: - Helpers

    private static let serverError = VenueAPIError.http(statusCode: 500)
    private static let offlineError = URLError(.notConnectedToInternet)

    private static func fixtureVenue(
        id: String,
        name: String,
        lat: Double,
        lng: Double,
        neighborhood: String,
        hoursRaw: String?,
        workScore: Int,
        laptopPolicy: String,
        venueType: String
    ) -> Venue {
        let observedAt = "2026-08-01T00:00:00Z"
        return Venue(
            id: id,
            name: name,
            lat: lat,
            lng: lng,
            address: "1 Fixture Place",
            neighborhood: neighborhood,
            borough: "Manhattan",
            hoursRaw: hoursRaw,
            vertical: "cafe",
            attributes: VenueAttributes(
                wifi: Claim(value: "fast", mbpsRange: [50, 120], source: "curated", confidence: 0.9, observedAt: observedAt),
                outlets: Claim(value: "plenty", source: "curated", confidence: 0.85, observedAt: observedAt),
                laptopPolicy: Claim(value: laptopPolicy, source: "curated", confidence: 0.9, observedAt: observedAt),
                noise: Claim(value: "moderate", source: "agent", confidence: 0.6, observedAt: observedAt),
                seating: Claim(value: "some", source: "agent", confidence: 0.6, observedAt: observedAt)
            ),
            vibeTags: ["fixture"],
            workScore: workScore,
            lastVerified: observedAt,
            distanceM: 120,
            venueType: venueType
        )
    }
}
