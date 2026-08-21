import Foundation

/// Deterministic stand-in for the venue engine used by UI tests and package
/// tests to pin degraded states (engine down, offline, empty, photo failures,
/// slow network). It is inert unless constructed; the app only constructs it
/// when launched with `-UITestScenario <name>` (see `UITestScenario` in the app
/// target). No network, no persistence, no UI entry point.
public struct ScenarioVenueService: VenueListing, VenueDetailServing, VenuePhotoServing, VenueObservationSubmitting, Sendable {
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
        /// The first venue fetch throws `URLError(.notConnectedToInternet)`;
        /// every later call succeeds with fixtures. Pins "reconnect recovers
        /// without relaunch" (brewdesk#28) — the retry path, not the network.
        case offlineThenRecovers
        /// 2,180 deterministic venues on a ~290 m grid around Union Square —
        /// matches the live dataset's venue count. The perf harness for
        /// brewdesk#54's map frame-timing measurements; health OK, photos `[]`.
        case manyVenues
    }

    public let scenario: Scenario
    private let attempts = AttemptCounter()
    /// Independent of `attempts`: `offlineThenRecovers` must fail the first
    /// observation submit even after the venue fetch consumed its own first
    /// failure (brewdesk#47 — the form's retry path).
    private let observationAttempts = AttemptCounter()

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
            // OSM syntax → the detail screen's structured hours + open-now
            // badge. UI tests pin the clock with -brewdesk.uitest-fixed-now.
            hoursRaw: "Mo-Fr 07:00-19:00; Sa-Su 08:00-18:00",
            workScore: 84,
            laptopPolicy: "unrestricted",
            venueType: "cafe",
            website: "https://fixture-roasters.example",
            phone: "+1 212-555-0142",
            email: "hello@fixture-roasters.example"
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
            // Deliberately NOT OSM syntax: pins the raw-string fallback
            // (never a wrong open/closed claim on unparseable hours).
            hoursRaw: "Daily 8am–5pm",
            workScore: 52,
            laptopPolicy: "discouraged",
            venueType: "cafe"
        )
    ]

    /// Deterministic venue-count-scale fixture (brewdesk#54): 2,180 venues on
    /// a 47-column grid (~290 m spacing, ~0.12° square) centred on Union
    /// Square, mirroring the live engine's dataset size. Scores cycle 0–100 so
    /// every tier renders. Lazily materialised — only the `manyVenues`
    /// scenario pays for it.
    public static let perfVenues: [Venue] = {
        let columns = 47
        let count = 2_180
        let step = 0.0026
        let originLat = 40.7359 - Double(columns - 1) / 2 * step
        let originLng = -73.9911 - Double(columns - 1) / 2 * step
        return (0..<count).map { index in
            fixtureVenue(
                id: "perf-\(index)",
                name: "Perf Cafe \(index)",
                lat: originLat + Double(index / columns) * step,
                lng: originLng + Double(index % columns) * step,
                neighborhood: "Perf Grid",
                hoursRaw: nil,
                workScore: (index * 37) % 101,
                laptopPolicy: "unrestricted",
                venueType: "cafe"
            )
        }
    }()

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
        case .offlineThenRecovers:
            if attempts.next() == 1 { throw Self.offlineError }
            return Self.fixtureVenues
        case .manyVenues:
            return Self.perfVenues
        case .fixtureOK, .photosEmpty, .photosFail:
            return Self.fixtureVenues
        }
    }

    public func fetchHealth() async throws -> HealthResponse? {
        switch scenario {
        case .engineDown: throw Self.serverError
        case .offline: throw Self.offlineError
        case .manyVenues:
            return HealthResponse(
                ok: true,
                venueCount: Self.perfVenues.count,
                seededAt: "2026-08-01T00:00:00Z",
                observationCount: 0
            )
        default: return Self.fixtureHealth
        }
    }

    // MARK: - VenueDetailServing

    public func fetchVenue(id: String) async throws -> Venue {
        switch scenario {
        case .engineDown: throw Self.serverError
        case .offline: throw Self.offlineError
        case .manyVenues:
            guard let venue = Self.perfVenues.first(where: { $0.id == id }) else {
                throw VenueAPIError.http(statusCode: 404)
            }
            return venue
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
        case .emptyVenues, .photosEmpty, .manyVenues: return []
        case .fixtureOK, .slow, .offlineThenRecovers: return Self.fixturePhotos
        }
    }

    // MARK: - VenueObservationSubmitting (brewdesk#47)

    /// Same degradation contract as the fetch paths, with one addition:
    /// `offlineThenRecovers` fails the FIRST submit and succeeds afterwards,
    /// pinning the form's error → Retry → thank-you path deterministically.
    @discardableResult
    public func submitObservation(
        venueId: String,
        submittedBy: String,
        answers: ObservationAnswers
    ) async throws -> Venue {
        switch scenario {
        case .engineDown: throw Self.serverError
        case .offline: throw Self.offlineError
        case .slow:
            try await Task.sleep(for: .seconds(6))
            return Self.observedVenue(id: venueId)
        case .offlineThenRecovers:
            if observationAttempts.next() == 1 { throw Self.offlineError }
            return Self.observedVenue(id: venueId)
        case .fixtureOK, .emptyVenues, .photosEmpty, .photosFail:
            return Self.observedVenue(id: venueId)
        }
    }

    /// The "rescored venue" a successful submit returns. Lenient on unknown
    /// ids (snapshot-seeded launches submit against non-fixture venues): the
    /// form ignores the payload, so the first fixture stands in.
    private static func observedVenue(id: String) -> Venue {
        fixtureVenues.first { $0.id == id } ?? fixtureVenues[0]
    }

    // MARK: - Helpers

    private static let serverError = VenueAPIError.http(statusCode: 500)
    private static let offlineError = URLError(.notConnectedToInternet)

    /// Per-service call counter so a value-type scenario can behave
    /// differently on its first call (`offlineThenRecovers`).
    private final class AttemptCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func next() -> Int { lock.withLock { count += 1; return count } }
    }

    private static func fixtureVenue(
        id: String,
        name: String,
        lat: Double,
        lng: Double,
        neighborhood: String,
        hoursRaw: String?,
        workScore: Int,
        laptopPolicy: String,
        venueType: String,
        website: String? = nil,
        phone: String? = nil,
        email: String? = nil
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
            venueType: venueType,
            website: website,
            phone: phone,
            email: email
        )
    }
}
