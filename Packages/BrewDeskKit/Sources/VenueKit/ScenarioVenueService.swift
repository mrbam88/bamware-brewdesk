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
        /// Venues OK; photos are one Google-attributed photo plus one approved
        /// community photo carrying `contributorName` (brewdesk#49) — pins the
        /// byline in the strip + viewer next to an unchanged Google photo.
        case communityPhotos
        /// Cupertino-area fixture venues (ve#46 tier 0 / bd#108): every venue
        /// carries `tier: "osm-baseline"`, claims sourced `osm`, and
        /// `fetchVenuesResult` reports `coverage: .baseline` — pins the
        /// honest banner + "OSM baseline · updated <date>" provenance
        /// wording for a viewport the engine has only OSM data for.
        case baselineCity
        /// Venues resolve to `[]` and `fetchVenuesResult` reports
        /// `coverage: .none` — the intentional empty state for a viewport
        /// the engine has nothing for at all. Distinct from `emptyVenues`,
        /// which decodes as `.researched` (the missing-field default) —
        /// `noCoverage` pins the coverage-driven path specifically.
        case noCoverage
        /// bd#200 — the regression fixture for "search must be city-wide":
        /// the normal three fixture venues near Union Square PLUS
        /// `farawayVenue`, a café in St. George, Staten Island — ~13.5km
        /// from Union Square, well outside any viewport radius
        /// (`VenuesModel.maxRadiusM` caps at 3km) but inside the citywide
        /// server-search radius (40km). A viewport query (`query.search ==
        /// nil`) never returns it — only `fetchVenuesResult` filtering on
        /// `query.search`, the same way the real engine's `q` param does,
        /// ever surfaces it. `SearchUITests` proves the far café is
        /// unreachable on `origin/main` (no server search existed) and
        /// reachable once bd#200's citywide search ships.
        case cityWideSearch
    }

    public let scenario: Scenario
    private let attempts = AttemptCounter()
    /// Independent of `attempts`: `offlineThenRecovers` must fail the first
    /// observation submit even after the venue fetch consumed its own first
    /// failure (brewdesk#47 — the form's retry path).
    private let observationAttempts = AttemptCounter()
    /// Photo fetches filter through the blocked-contributors list
    /// (brewdesk#48) so "block hides their photos" is testable end-to-end.
    /// Injectable for package tests; the shared store is in-memory under
    /// `-UITestScenario`, so scenario launches stay deterministic.
    private let blockStore: ContributorBlockStore

    public init(scenario: Scenario, blockStore: ContributorBlockStore = .shared) {
        self.scenario = scenario
        self.blockStore = blockStore
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
            email: "hello@fixture-roasters.example",
            // bd#180: the one fixture that carries `news` — pins the "In the
            // press" row rendering (title + source domain, tap opens URL).
            // Two entries so the UI test can assert both a titled row and a
            // title-less row (falls back to the domain).
            news: [
                NewsLink(
                    url: "https://fixture-press.example/roasters-review",
                    title: "Fixture Roasters is the best laptop café in the neighborhood",
                    sourceDomain: "fixture-press.example",
                    observedAt: "2026-07-15",
                    tag: "news"
                ),
                NewsLink(
                    url: "https://fixture-gazette.example/roasters",
                    sourceDomain: "fixture-gazette.example",
                    observedAt: "2026-06-01",
                    tag: "news"
                )
            ]
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
        ),
        // bd#159: every claim is an `estimate` — `Venue.isObserved` is
        // false, so this venue must render "Not checked yet" everywhere
        // instead of `workScore`, and sort after the three venues above in
        // `model.venues`. `workScore` (52) matches the neutral fallback
        // ve#64 actually returns for unobserved NYC venues, on purpose —
        // it's the same number Roasters/Reading Room/Corner Cafe could
        // never legitimately show as their OWN measured score. Seating
        // stays "some" like the other fixtures so the honest-zero filter
        // test (`FilterUITests`) still empties out at a "Plenty" floor.
        unobservedFixtureVenue(
            id: "fixture-unchecked",
            name: "Fixture Unchecked Spot",
            lat: 40.7368, lng: -73.9852,
            neighborhood: "Union Square"
        )
    ]

    /// bd#200 — St. George, Staten Island: ~13.5km from `fixtureVenues`'
    /// Union Square cluster, outside every viewport radius `VenuesModel`
    /// ever queries with (max 3km) but inside the citywide server-search
    /// radius (40km). Only `.cityWideSearch`'s `fetchVenuesResult` ever
    /// returns it, and only when `query.search` matches its name/
    /// neighborhood — a viewport-only fetch (`query.search == nil`) never
    /// does, the exact shape of the bd#200 bug.
    public static let farawayVenue: Venue = fixtureVenue(
        id: "fixture-faraway",
        name: "Fixture Ferry Roasters",
        lat: 40.6437, lng: -74.0787,
        neighborhood: "St. George",
        hoursRaw: "Mo-Su 06:00-20:00",
        workScore: 77,
        laptopPolicy: "unrestricted",
        venueType: "cafe"
    )

    /// bd#219 (supervisor 2nd revision): five more cafés clustered within a
    /// few hundred metres of `farawayVenue`, in St. George — a search
    /// selection's own surroundings reload (`model.updateViewport` around
    /// the SELECTED café, not the original Union Square viewport) needs
    /// something real to find nearby, or `map-rendered-marker-count`'s "≥5
    /// other markers visible after the surroundings load" UI-test
    /// assertion has nothing to prove against. Only ever returned by
    /// `.cityWideSearch`'s viewport-only `fetchVenuesResult` when the
    /// QUERIED coordinate is itself near St. George — see
    /// `isNearFarawayVenue(_:)`.
    /// bd#219 (supervisor 2nd revision): a dozen cafés spread over roughly
    /// 200-400m around `farawayVenue` — comfortably inside a walking-scale
    /// viewport, spread widely enough that `MapAnnotationPlanner`'s own
    /// screen-space collision/demotion logic (bd#209/#212 — tightly
    /// clustered points can collide and get skipped, not just demoted)
    /// doesn't leave fewer than the "≥5 other markers visible after the
    /// surroundings load" UI-test assertion needs. More than the test
    /// strictly requires, deliberately, for margin.
    private static let farawaySurroundingVenues: [Venue] = [
        fixtureVenue(
            id: "fixture-faraway-2", name: "Fixture Ferry Terminal Coffee",
            lat: 40.6455, lng: -74.0790, neighborhood: "St. George",
            hoursRaw: "Mo-Su 06:00-20:00", workScore: 68, laptopPolicy: "unrestricted", venueType: "cafe"
        ),
        fixtureVenue(
            id: "fixture-faraway-3", name: "Fixture Richmond Terrace Roasters",
            lat: 40.6420, lng: -74.0784, neighborhood: "St. George",
            hoursRaw: "Mo-Su 07:00-19:00", workScore: 61, laptopPolicy: "unrestricted", venueType: "cafe"
        ),
        fixtureVenue(
            id: "fixture-faraway-4", name: "Fixture Borough Hall Brew",
            lat: 40.6437, lng: -74.0820, neighborhood: "St. George",
            hoursRaw: "Mo-Su 07:00-19:00", workScore: 55, laptopPolicy: "unrestricted", venueType: "cafe"
        ),
        fixtureVenue(
            id: "fixture-faraway-5", name: "Fixture Van Duzer Coffee",
            lat: 40.6437, lng: -74.0754, neighborhood: "St. George",
            hoursRaw: "Mo-Su 06:30-18:30", workScore: 49, laptopPolicy: "unrestricted", venueType: "cafe"
        ),
        fixtureVenue(
            id: "fixture-faraway-6", name: "Fixture Bay Street Grind",
            lat: 40.6460, lng: -74.0810, neighborhood: "St. George",
            hoursRaw: "Mo-Su 07:00-20:00", workScore: 63, laptopPolicy: "unrestricted", venueType: "cafe"
        ),
        fixtureVenue(
            id: "fixture-faraway-7", name: "Fixture Slosson Terrace Roasters",
            lat: 40.6415, lng: -74.0810, neighborhood: "St. George",
            hoursRaw: "Mo-Su 07:00-19:00", workScore: 58, laptopPolicy: "unrestricted", venueType: "cafe"
        ),
        fixtureVenue(
            id: "fixture-faraway-8", name: "Fixture Hyatt Street Coffee",
            lat: 40.6460, lng: -74.0760, neighborhood: "St. George",
            hoursRaw: "Mo-Su 07:00-19:00", workScore: 52, laptopPolicy: "unrestricted", venueType: "cafe"
        ),
        fixtureVenue(
            id: "fixture-faraway-9", name: "Fixture Wall Street St. George Brew",
            lat: 40.6415, lng: -74.0760, neighborhood: "St. George",
            hoursRaw: "Mo-Su 07:00-19:00", workScore: 47, laptopPolicy: "unrestricted", venueType: "cafe"
        ),
        fixtureVenue(
            id: "fixture-faraway-10", name: "Fixture Stuyvesant Place Grind",
            lat: 40.6470, lng: -74.0787, neighborhood: "St. George",
            hoursRaw: "Mo-Su 07:00-19:00", workScore: 44, laptopPolicy: "unrestricted", venueType: "cafe"
        ),
        fixtureVenue(
            id: "fixture-faraway-11", name: "Fixture Central Avenue Coffee",
            lat: 40.6404, lng: -74.0787, neighborhood: "St. George",
            hoursRaw: "Mo-Su 07:00-19:00", workScore: 41, laptopPolicy: "unrestricted", venueType: "cafe"
        ),
    ]

    /// Within ~5km of `farawayVenue` — comfortably covers any walking-scale
    /// viewport a search-selection fly-to's own surroundings reload would
    /// query with, while staying well clear of the ~13.5km distance from
    /// the default Union Square viewport (bd#200's own test already relies
    /// on that separation).
    private static func isNearFarawayVenue(lat: Double, lng: Double) -> Bool {
        metersBetween(lat, lng, farawayVenue.lat, farawayVenue.lng) < 5_000
    }

    private static func metersBetween(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let earthRadiusM = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return earthRadiusM * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

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

    /// Five Cupertino-area venues (ve#46 tier 0 / bd#108): real coffee-shop
    /// names near Apple Park, OSM-sourced claims, `tier: "osm-baseline"`.
    /// `ReviewerSimulationTests` asserts ≥5 rows/pins against this fixture —
    /// the app-side stand-in for what the engine's OSM baseline import will
    /// answer for any US viewport once ve#46 ships.
    public static let baselineVenues: [Venue] = [
        baselineVenue(id: "baseline-main-street", name: "Main Street Coffee", lat: 37.3220, lng: -122.0125, neighborhood: "Cupertino", workScore: 58),
        baselineVenue(id: "baseline-homestead", name: "Homestead Coffee House", lat: 37.3268, lng: -122.0322, neighborhood: "Cupertino", workScore: 61),
        baselineVenue(id: "baseline-de-anza", name: "De Anza Reading Room", lat: 37.3187, lng: -122.0453, neighborhood: "Cupertino", workScore: 55),
        baselineVenue(id: "baseline-bandley", name: "Bandley Drive Grounds", lat: 37.3306, lng: -122.0296, neighborhood: "Cupertino", workScore: 60),
        baselineVenue(id: "baseline-stevens-creek", name: "Stevens Creek Roasters", lat: 37.3172, lng: -122.0311, neighborhood: "Cupertino", workScore: 57),
    ]

    public static let fixtureHealth = HealthResponse(
        ok: true,
        venueCount: fixtureVenues.count,
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

    /// `communityPhotos` payload (brewdesk#49): index 0 keeps the Google
    /// attribution contract untouched; index 1 is an approved community photo
    /// — `contributorName`, no Google attribution. Same closed-port URLs as
    /// `fixturePhotos` (deterministic load failure; the byline renders
    /// regardless of image bytes).
    public static let fixtureCommunityPhotos: [VenuePhoto] = [
        fixturePhotos[0],
        VenuePhoto(
            url: "http://127.0.0.1:9/fixture-photo-community.jpg",
            widthPx: 1200,
            heightPx: 900,
            contributorName: "Ada L."
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
        case .fixtureOK, .photosEmpty, .photosFail, .communityPhotos:
            return Self.fixtureVenues
        case .baselineCity:
            return Self.baselineVenues
        case .noCoverage:
            return []
        case .cityWideSearch:
            // A viewport-only fetch (no `q`) never sees the far café —
            // `fetchVenuesResult` below is the only path that can.
            return Self.fixtureVenues
        }
    }

    /// `fetchVenues` above stays the venues-only source of truth for every
    /// existing scenario; only `baselineCity`/`noCoverage`/`cityWideSearch`
    /// need a DIFFERENT venue list. Every scenario's `fetchVenuesResult`
    /// (including these three) now also honors `query.search` the way the
    /// real engine's `q` param does (bd#200) — VenuesModel's new citywide
    /// search calls `fetchVenuesResult` with `search` set on every
    /// scenario, not just `cityWideSearch`; without this, e.g. `fixtureOK`
    /// would hand back all its venues unfiltered for ANY search text,
    /// which VenuesModel would then (correctly) treat as new city-wide
    /// matches and re-union into `venues` — silently undoing the existing
    /// local-search fixtures' "narrows to just this venue" assertions.
    public func fetchVenuesResult(_ query: VenueQuery) async throws -> VenueLoadResult {
        switch scenario {
        case .baselineCity:
            return VenueLoadResult(venues: Self.filteringSearch(query, in: Self.baselineVenues), coverage: .baseline)
        case .noCoverage:
            return VenueLoadResult(venues: [], coverage: .none)
        case .cityWideSearch:
            // bd#200: mirrors the real engine's `q` contract over EVERY
            // venue this scenario knows about (fixtures + the far café),
            // not just the ones a viewport fetch would have returned. No
            // `q` (or an empty one) is a plain viewport fetch — bd#200's
            // own default (Union Square) never includes the far café; bd#219
            // (supervisor 2nd revision) adds the ONE exception: a viewport
            // fetch queried NEAR St. George (a search-selection's own
            // surroundings reload, after flying the camera there) returns
            // the far café plus its five neighbours instead, so that reload
            // has real surrounding markers to find — mirroring what a real
            // geo-aware server would answer for that location.
            guard let search = query.search, !search.isEmpty else {
                if let lat = query.lat, let lng = query.lng, Self.isNearFarawayVenue(lat: lat, lng: lng) {
                    return VenueLoadResult(
                        venues: [Self.farawayVenue] + Self.farawaySurroundingVenues, coverage: .researched
                    )
                }
                return VenueLoadResult(venues: Self.fixtureVenues, coverage: .researched)
            }
            return VenueLoadResult(venues: Self.filteringSearch(query, in: Self.venuesIncludingFaraway), coverage: .researched)
        default:
            let venues = try await fetchVenues(query)
            return VenueLoadResult(venues: Self.filteringSearch(query, in: venues), coverage: .researched)
        }
    }

    /// bd#200: case/diacritic-insensitive contains over name or
    /// neighborhood, matching `VenueSearch.apply`'s own normalization — the
    /// deterministic stand-in for the real engine's `q` filtering. A `nil`
    /// or empty `query.search` (every existing viewport-load call site)
    /// returns `venues` unchanged.
    private static func filteringSearch(_ query: VenueQuery, in venues: [Venue]) -> [Venue] {
        guard let search = query.search, !search.isEmpty else { return venues }
        let needle = search.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return venues.filter { venue in
            let name = venue.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let neighborhood = venue.neighborhood.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return name.contains(needle) || neighborhood.contains(needle)
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
        case .baselineCity:
            return HealthResponse(
                ok: true,
                venueCount: Self.baselineVenues.count,
                seededAt: "2026-08-10T00:00:00Z",
                observationCount: 0
            )
        case .noCoverage:
            return HealthResponse(ok: true, venueCount: 0, seededAt: "2026-08-10T00:00:00Z", observationCount: 0)
        default: return Self.fixtureHealth
        }
    }

    private static let venuesIncludingFaraway = fixtureVenues + [farawayVenue]

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
        case .baselineCity:
            guard let venue = Self.baselineVenues.first(where: { $0.id == id }) else {
                throw VenueAPIError.http(statusCode: 404)
            }
            return venue
        case .noCoverage:
            throw VenueAPIError.http(statusCode: 404)
        case .cityWideSearch:
            guard let venue = (Self.venuesIncludingFaraway + Self.farawaySurroundingVenues).first(where: { $0.id == id }) else {
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
        case .emptyVenues, .photosEmpty, .manyVenues, .baselineCity, .noCoverage, .cityWideSearch: return []
        case .fixtureOK, .slow, .offlineThenRecovers:
            return blockStore.filteringBlocked(Self.fixturePhotos)
        case .communityPhotos:
            return blockStore.filteringBlocked(Self.fixtureCommunityPhotos)
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
        case .fixtureOK, .emptyVenues, .photosEmpty, .photosFail, .manyVenues, .communityPhotos,
             .baselineCity, .noCoverage, .cityWideSearch:
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
        email: String? = nil,
        news: [NewsLink]? = nil
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
            email: email,
            news: news
        )
    }

    /// bd#159 / brewdesk#213 fixture venue: every scored claim is
    /// `source: "estimate"`, so `Venue.isObserved` is false — the
    /// deterministic stand-in for a venue the engine has never actually
    /// checked, as opposed to `baselineVenue` below (OSM-sourced, still
    /// counts as observed at confidence 0.4). Carries an EXPLICIT
    /// `scoreDisplay: .notRated` (brewdesk#213) rather than relying on the
    /// `.notProvided`/`isObserved` fallback alone — this is the fixture the
    /// ticket's UI test targets: a venue whose server payload is the modern
    /// `scoreDisplay: null` contract, not just the older heuristic.
    private static func unobservedFixtureVenue(
        id: String,
        name: String,
        lat: Double,
        lng: Double,
        neighborhood: String
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
            hoursRaw: nil,
            vertical: "cafe",
            attributes: VenueAttributes(
                wifi: Claim(value: "unknown", source: "estimate", confidence: 0.3, observedAt: observedAt),
                outlets: Claim(value: "unknown", source: "estimate", confidence: 0.3, observedAt: observedAt),
                laptopPolicy: Claim(value: "unrestricted", source: "estimate", confidence: 0.3, observedAt: observedAt),
                noise: Claim(value: "unknown", source: "estimate", confidence: 0.3, observedAt: observedAt),
                // Matches the other fixtures' "some" so a "Plenty" seating
                // floor still empties the list honestly (`FilterUITests`).
                seating: Claim(value: "some", source: "estimate", confidence: 0.3, observedAt: observedAt)
            ),
            vibeTags: ["fixture"],
            workScore: 52,
            lastVerified: nil,
            distanceM: 260,
            venueType: "cafe",
            scoreDisplay: .notRated
        )
    }

    /// OSM-baseline fixture venue (ve#46 tier 0 / bd#108): every claim is
    /// `source: "osm"`, unverified confidence, and the venue carries
    /// `tier: "osm-baseline"` — never "curated", never a human source, so
    /// `ProvenanceStamp` renders the baseline wording, not a seal.
    private static func baselineVenue(
        id: String,
        name: String,
        lat: Double,
        lng: Double,
        neighborhood: String,
        workScore: Int
    ) -> Venue {
        let observedAt = "2026-08-10T00:00:00Z"
        return Venue(
            id: id,
            name: name,
            lat: lat,
            lng: lng,
            address: nil,
            neighborhood: neighborhood,
            borough: "Santa Clara County",
            hoursRaw: nil,
            vertical: "cafe",
            attributes: VenueAttributes(
                wifi: Claim(value: "unknown", source: "osm", confidence: 0.4, observedAt: observedAt),
                outlets: Claim(value: "unknown", source: "osm", confidence: 0.4, observedAt: observedAt),
                laptopPolicy: Claim(value: "unrestricted", source: "osm", confidence: 0.4, observedAt: observedAt),
                noise: Claim(value: "unknown", source: "osm", confidence: 0.4, observedAt: observedAt)
            ),
            vibeTags: [],
            workScore: workScore,
            lastVerified: nil,
            distanceM: nil,
            venueType: "cafe",
            tier: "osm-baseline"
        )
    }
}
