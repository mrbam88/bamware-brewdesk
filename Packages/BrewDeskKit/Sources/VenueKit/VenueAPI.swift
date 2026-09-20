import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum VenueAPIError: Error, LocalizedError, Sendable, Equatable {
    case badURL
    case invalidResponse
    case http(statusCode: Int)
    case decoding
    case unsupportedSpeedTest
    /// A community write (venue-engine PR #145 `communityAuth`) came back 401
    /// while a bearer token WAS attached: a forced refresh either failed (no
    /// session, or the server rejected the refresh token) or the retried
    /// request also came back 401. Callers should surface a sign-in prompt
    /// and keep the user's draft — not treat this as a generic engine
    /// failure. A signed-out 401 (no token was ever attached) is never
    /// remapped to this case; see `VenueAPI.postAuthenticated` — bd#202's
    /// explicit "signed-out behaviour unchanged" scope guard.
    case authenticationRequired

    public var errorDescription: String? {
        switch self {
        case .badURL:
            "The venue request could not be created."
        case .invalidResponse:
            "The venue service returned an invalid response."
        case .http(let statusCode):
            "The venue service returned HTTP \(statusCode)."
        case .decoding:
            "The venue service returned data in an unexpected format."
        case .unsupportedSpeedTest:
            "Speed observations require a remote HTTPS venue service."
        case .authenticationRequired:
            "Sign in to submit."
        }
    }
}

public protocol VenueListing: Sendable {
    func fetchVenues(_ query: VenueQuery) async throws -> [Venue]
    /// Venues plus the engine's reported coverage for the viewport (ve#46,
    /// bd#108). Optional capability: the default extension answers
    /// `.researched` by delegating to `fetchVenues`, so every existing
    /// conformer (mocks, `ScenarioVenueService` scenarios that don't care)
    /// keeps compiling and behaving exactly as before without adopting this.
    func fetchVenuesResult(_ query: VenueQuery) async throws -> VenueLoadResult
    /// Dataset-level stats for the stat strip. Optional capability: the
    /// default returns nil and the UI renders nothing.
    func fetchHealth() async throws -> HealthResponse?
}

extension VenueListing {
    public func fetchHealth() async throws -> HealthResponse? { nil }
    public func fetchVenuesResult(_ query: VenueQuery) async throws -> VenueLoadResult {
        VenueLoadResult(venues: try await fetchVenues(query), coverage: .researched)
    }
}

public protocol VenueDetailServing: Sendable {
    func fetchVenue(id: String) async throws -> Venue
}

public protocol VenuePhotoServing: Sendable {
    /// Display-only photos for a venue; [] whenever the engine has none.
    func fetchPhotos(venueId: String) async throws -> [VenuePhoto]
}

public protocol VenueMeasuring: Sendable {
    var supportsSpeedTest: Bool { get }
    func submitSpeedTest(venueId: String, mbpsDown: Double) async throws -> Venue
    func measureDownloadMbps(samples: Int) async throws -> Double
}

/// Async client for the bamware-venue-engine master API.
/// The iOS Simulator reaches `http://localhost:3000` on the host Mac directly.
/// The app target permits local HTTP networking in its Debug configuration.
public struct VenueAPI: VenueListing, VenueDetailServing, VenueMeasuring, VenuePhotoServing, VenueObservationSubmitting, Sendable {
    public static var defaultBaseURL: URL {
        #if DEBUG
        URL(string: "http://localhost:3000")!
        #else
        URL(string: "https://venuekit-ashen.vercel.app")!
        #endif
    }

    public let baseURL: URL
    private let session: URLSession
    private let blockStore: ContributorBlockStore
    /// Returns a fresh bearer token for the signed-in user, or `nil` when
    /// signed out — same shape `ServerSavedVenuePersistence.tokenProvider`
    /// already uses for saved-spots sync (bamware-brewdesk#175). Production
    /// wiring: `BrewDeskAccountTenant.freshAccessToken`, which already does
    /// its own proactive refresh. Defaulting to `{ nil }` keeps every
    /// existing call site (tests, the GET-only `VenueAPI()` instances in
    /// `RootView`) byte-identical to pre-bd#202 behavior: no header, no
    /// retry, nothing sent that wasn't sent before.
    private let tokenProvider: @Sendable () async -> String?
    /// Forces one refresh after a signed-in write comes back 401 — the one
    /// case `tokenProvider`'s own proactive check can miss (the access
    /// token's own `exp` still looked fine; the server revoked the session
    /// some other way). Production wiring:
    /// `BrewDeskAccountTenant.refreshAccessTokenAfterUnauthorized`, which
    /// forces the network refresh call rather than trusting the cached
    /// expiry. Returns `nil` on no session or a failed refresh.
    private let tokenRefresher: @Sendable () async -> String?

    /// Fail fast: a stalled engine becomes a Retry state in 15 s, not the
    /// 60 s `URLSession.shared` default. No `waitsForConnectivity` — offline
    /// should surface as an explicit error state with a Retry, not a hang.
    public static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    public init(
        baseURL: URL = VenueAPI.defaultBaseURL,
        session: URLSession = VenueAPI.defaultSession,
        blockStore: ContributorBlockStore = .shared,
        tokenProvider: @escaping @Sendable () async -> String? = { nil },
        tokenRefresher: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.blockStore = blockStore
        self.tokenProvider = tokenProvider
        self.tokenRefresher = tokenRefresher
    }

    public var supportsSpeedTest: Bool {
        baseURL.scheme == "https" && baseURL.host != "localhost" && baseURL.host != "127.0.0.1"
    }

    public func fetchVenues(_ query: VenueQuery) async throws -> [Venue] {
        try await fetchVenuesResult(query).venues
    }

    /// Always the real queried viewport — no client-side "outside NYC"
    /// substitution (bd#108 removed that; `VenuesModel` now sends whatever
    /// coordinate it was given). `coverage` on the response says whether
    /// that viewport is researched, OSM baseline, or has nothing at all.
    ///
    /// bd#192: the highest `limit` this client falls back to when the live
    /// engine rejects a bigger request — `schema.ts`'s documented cap as of
    /// this ticket (`limit.max(200)`), so a `VenuesModel.viewportQueryLimit`
    /// request (500, ahead of the companion server ticket ve#140 raising
    /// the cap) still degrades to a working map instead of a hard failure
    /// if this ships before that server change lands.
    static let fallbackLimit = 200

    /// Coordinates travel in `X-BrewDesk-Viewport` (engine #16), never in
    /// the URL query string, so they are not retained as Vercel Search Params
    /// (brewdesk#154). Filters stay on the query string.
    ///
    /// bd#192: retries once at `Self.fallbackLimit` on an HTTP 400 when the
    /// requested `limit` exceeds it — the one, deliberately narrow case a
    /// stricter-than-expected server `limit` cap must not turn into a
    /// user-visible failed map. Any other 400 (a genuinely bad query) still
    /// surfaces as `.http(400)` on the first attempt, unchanged.
    public func fetchVenuesResult(_ query: VenueQuery) async throws -> VenueLoadResult {
        do {
            return try await performFetchVenuesResult(query)
        } catch VenueAPIError.http(let statusCode) where statusCode == 400 && query.limit > Self.fallbackLimit {
            var fallback = query
            fallback.limit = Self.fallbackLimit
            return try await performFetchVenuesResult(fallback)
        }
    }

    private func performFetchVenuesResult(_ query: VenueQuery) async throws -> VenueLoadResult {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/v1/venues"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = query.urlQueryItems
        guard let url = comps.url else { throw VenueAPIError.badURL }
        var request = URLRequest(url: url)
        if let viewport = query.viewportHeaderValue {
            request.setValue(viewport, forHTTPHeaderField: VenueQuery.viewportHeaderName)
        }
        let response = try await get(VenueListResponse.self, request: request)
        return VenueLoadResult(venues: response.venues, coverage: .from(response.resolvedCoverage))
    }

    public func fetchHealth() async throws -> HealthResponse? {
        try await get(HealthResponse.self, from: baseURL.appendingPathComponent("/v1/health"))
    }

    public func fetchVenue(id: String) async throws -> Venue {
        try await get(
            VenueDetailResponse.self,
            from: baseURL.appendingPathComponent("/v1/venues/\(id)")
        ).venue
    }

    public func fetchPhotos(venueId: String) async throws -> [VenuePhoto] {
        let response = try await get(
            VenuePhotosResponse.self,
            from: baseURL.appendingPathComponent("/v1/venues/\(venueId)/photos")
        )
        // Device-local block filter (brewdesk#48/#66): the live path filters
        // through the same store as ScenarioVenueService, so blocking hides
        // a contributor's photos on the next real fetch too.
        return blockStore.filteringBlocked(response.photos.map { photo in
            VenuePhoto(
                url: Self.absolutePhotoURL(photo.url, base: baseURL),
                attribution: photo.attribution,
                attributionUri: photo.attributionUri,
                widthPx: photo.widthPx,
                heightPx: photo.heightPx,
                contributorName: photo.contributorName
            )
        })
    }

    /// Production returns Google's `photoUri` verbatim (host
    /// `lh3.googleusercontent.com`), already absolute, so this is a no-op for
    /// every real payload. The relative-path branch only resolves a
    /// same-origin `/v1/venues/…/media` path if the engine ever sends one;
    /// none do today (brewdesk#156). Kept so ScenarioVenueService fixtures
    /// and future relative payloads still resolve against the active base URL.
    static func absolutePhotoURL(_ url: String, base: URL) -> String {
        guard url.hasPrefix("/") else { return url }
        return base.appendingPathComponent(url).absoluteString
    }

    public func fetchNeighborhoods() async throws -> [NeighborhoodsResponse.Hood] {
        try await get(NeighborhoodsResponse.self, from: baseURL.appendingPathComponent("/v1/neighborhoods")).neighborhoods
    }

    /// The data flywheel: submit a measured download speed; the engine updates
    /// the wifi claim (source=speed_test, confidence 0.9) and rescores.
    @discardableResult
    public func submitSpeedTest(venueId: String, mbpsDown: Double) async throws -> Venue {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/observations"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(
            ObservationRequest(venueId: venueId, kind: "speed_test", mbpsDown: mbpsDown)
        )
        return try await postAuthenticated(ObservationResponse.self, request: req).venue
    }

    /// Rough downstream estimate from uncached JSON fetches against a remote
    /// HTTPS service. A dedicated known-size payload should replace this before
    /// production measurement claims are enabled.
    public func measureDownloadMbps(samples: Int = 3) async throws -> Double {
        guard supportsSpeedTest else { throw VenueAPIError.unsupportedSpeedTest }
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/v1/venues"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            .init(name: "limit", value: "200"),
            .init(name: "_speed_test_nonce", value: UUID().uuidString)
        ]
        guard let url = comps.url else { throw VenueAPIError.badURL }

        var totalBytes = 0.0
        var totalSeconds = 0.0
        for _ in 0..<max(samples, 1) {
            let start = Date()
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, resp) = try await session.data(for: request)
            try Self.check(resp)
            totalSeconds += Date().timeIntervalSince(start)
            totalBytes += Double(data.count)
        }
        let mbps = (totalBytes * 8 / 1_000_000) / max(totalSeconds, 0.001)
        return min((mbps * 10).rounded() / 10, 500)
    }

    /// Structured community observation (brewdesk#47, #79): the five enum answers
    /// become community claims (source `user_report`) and the venue is
    /// rescored. Contract: bamware-venue-engine PR #26 —
    /// `POST /v1/venues/:id/observations`; 401 = missing/empty submitter,
    /// 400 = anything outside the enum vocabulary (both surface as `.http`).
    @discardableResult
    public func submitObservation(
        venueId: String,
        submittedBy: String,
        answers: ObservationAnswers
    ) async throws -> Venue {
        var req = URLRequest(
            url: baseURL.appendingPathComponent("/v1/venues/\(venueId)/observations")
        )
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(
            VenueObservationRequest(submittedBy: submittedBy, answers: answers)
        )
        return try await postAuthenticated(ObservationResponse.self, request: req).venue
    }

    private func get<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        try await get(type, request: URLRequest(url: url))
    }

    private func get<T: Decodable>(_ type: T.Type, request: URLRequest) async throws -> T {
        let (data, resp) = try await session.data(for: request)
        try Self.check(resp)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch is DecodingError {
            throw VenueAPIError.decoding
        }
    }

    /// The community-write seam (venue-engine PR #145 `communityAuth`) every
    /// bearer-carrying POST routes through. Attaches `Authorization` when
    /// `tokenProvider` has a token; on a 401 while one WAS attached, forces
    /// exactly one refresh (`tokenRefresher`) and retries exactly once with
    /// the new token before giving up — see `VenueAPIError.authenticationRequired`.
    /// A signed-out request (no token to begin with) is sent exactly as it
    /// was before bd#202, and its 401 (if any) surfaces unchanged as
    /// `.http(statusCode: 401)` — the ticket's explicit "signed-out
    /// behaviour unchanged" scope guard.
    private func postAuthenticated<T: Decodable>(_ type: T.Type, request: URLRequest) async throws -> T {
        let token = await tokenProvider()
        do {
            return try await get(type, request: authorized(request, token: token))
        } catch VenueAPIError.http(statusCode: 401) where token != nil {
            guard let refreshed = await tokenRefresher() else {
                throw VenueAPIError.authenticationRequired
            }
            do {
                return try await get(type, request: authorized(request, token: refreshed))
            } catch VenueAPIError.http(statusCode: 401) {
                throw VenueAPIError.authenticationRequired
            }
        }
    }

    private func authorized(_ request: URLRequest, token: String?) -> URLRequest {
        guard let token else { return request }
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func check(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else { throw VenueAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw VenueAPIError.http(statusCode: http.statusCode)
        }
    }
}
