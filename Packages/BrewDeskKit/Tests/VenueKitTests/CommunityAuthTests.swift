import Foundation
import Testing
@testable import VenueKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// venue-engine PR #145 `communityAuth` contract (bamware-brewdesk#202):
/// `VenueAPI`'s two bearer-carrying community writes (`POST /v1/observations`,
/// `POST /v1/venues/:id/observations`) attach `Authorization` when signed in,
/// leave it off entirely when signed out, and on a signed-in 401 force
/// exactly one refresh and retry before surfacing
/// `VenueAPIError.authenticationRequired`. Own recording protocol (not
/// `RecordingURLProtocol`/`ObservationRecordingProtocol`) so this suite can
/// script per-token responses without disturbing suites that run in
/// parallel — same reasoning `ReportBlockTests`' `PhotoStubURLProtocol`
/// gives for its own stub.
@Suite(.serialized) struct CommunityAuthTests {
    static let engine = URL(string: "https://venuekit-ashen.vercel.app")!

    private var answers: ObservationAnswers {
        ObservationAnswers(
            laptopFriendlyToday: .yes,
            seatsAvailable: .plenty,
            outletsWorking: .few,
            noise: .quiet,
            wifiQuality: .fast
        )
    }

    // MARK: - Header presence

    @Test func headerPresentWhenSignedIn() async throws {
        AuthAwareStubProtocol.reset()
        AuthAwareStubProtocol.script = AuthAwareStubProtocol.alwaysSucceed
        let api = VenueAPI(
            baseURL: Self.engine,
            session: AuthAwareStubProtocol.makeSession(),
            tokenProvider: { "good-token" },
            tokenRefresher: { Issue.record("refresher should not run on a first-try success"); return nil }
        )

        _ = try await api.submitObservation(venueId: "v1", submittedBy: "device-1", answers: answers)

        let requests = AuthAwareStubProtocol.requests
        #expect(requests.count == 1)
        #expect(requests[0].headerValue("Authorization") == "Bearer good-token")
    }

    @Test func headerAbsentWhenSignedOut() async throws {
        AuthAwareStubProtocol.reset()
        AuthAwareStubProtocol.script = AuthAwareStubProtocol.alwaysSucceed
        let api = VenueAPI(
            baseURL: Self.engine,
            session: AuthAwareStubProtocol.makeSession(),
            tokenProvider: { nil },
            tokenRefresher: { Issue.record("refresher should not run when signed out"); return nil }
        )

        _ = try await api.submitObservation(venueId: "v1", submittedBy: "device-1", answers: answers)

        let requests = AuthAwareStubProtocol.requests
        #expect(requests.count == 1)
        #expect(requests[0].headerValue("Authorization") == nil)
    }

    /// `submitSpeedTest` (`POST /v1/observations`) routes through the exact
    /// same seam — pinned once here so a future refactor can't silently
    /// special-case one write and not the other.
    @Test func speedTestAlsoCarriesTheHeaderWhenSignedIn() async throws {
        AuthAwareStubProtocol.reset()
        AuthAwareStubProtocol.script = AuthAwareStubProtocol.alwaysSucceed
        let api = VenueAPI(
            baseURL: Self.engine,
            session: AuthAwareStubProtocol.makeSession(),
            tokenProvider: { "good-token" },
            tokenRefresher: { nil }
        )

        _ = try await api.submitSpeedTest(venueId: "v1", mbpsDown: 42)

        let requests = AuthAwareStubProtocol.requests
        #expect(requests.count == 1)
        #expect(requests[0].path == "/v1/observations")
        #expect(requests[0].headerValue("Authorization") == "Bearer good-token")
    }

    // MARK: - 401 → refresh → retry once → success

    @Test func fourOhOneRefreshesAndRetriesOnceThenSucceeds() async throws {
        AuthAwareStubProtocol.reset()
        AuthAwareStubProtocol.script = { request in
            switch request.headerValue("Authorization") {
            case "Bearer expired-token": return (401, AuthAwareStubProtocol.errorBody)
            case "Bearer fresh-token": return AuthAwareStubProtocol.succeed(request)
            default: return (401, AuthAwareStubProtocol.errorBody)
            }
        }
        let api = VenueAPI(
            baseURL: Self.engine,
            session: AuthAwareStubProtocol.makeSession(),
            tokenProvider: { "expired-token" },
            tokenRefresher: { "fresh-token" }
        )

        let venue = try await api.submitObservation(venueId: "v1", submittedBy: "device-1", answers: answers)
        #expect(!venue.id.isEmpty)

        let requests = AuthAwareStubProtocol.requests
        #expect(requests.count == 2)
        #expect(requests[0].headerValue("Authorization") == "Bearer expired-token")
        #expect(requests[1].headerValue("Authorization") == "Bearer fresh-token")
        // Retry is the exact same write, not a different request shape.
        #expect(requests[0].path == requests[1].path)
        #expect(requests[0].body == requests[1].body)
    }

    // MARK: - 401 twice → authenticationRequired

    @Test func fourOhOneTwiceSurfacesAuthenticationRequired() async throws {
        AuthAwareStubProtocol.reset()
        AuthAwareStubProtocol.script = { _ in (401, AuthAwareStubProtocol.errorBody) }
        let api = VenueAPI(
            baseURL: Self.engine,
            session: AuthAwareStubProtocol.makeSession(),
            tokenProvider: { "expired-token" },
            tokenRefresher: { "still-bad-token" }
        )

        await #expect(throws: VenueAPIError.authenticationRequired) {
            try await api.submitObservation(venueId: "v1", submittedBy: "device-1", answers: answers)
        }
        // Exactly the initial try + one retry — never an unbounded loop.
        #expect(AuthAwareStubProtocol.requests.count == 2)
    }

    /// A refresh that can't produce a token at all (no session, or the
    /// server rejected the refresh token) skips the retry entirely — no
    /// second request is sent with a token known to be worthless.
    @Test func refreshFailureSurfacesAuthenticationRequiredWithoutARetryRequest() async throws {
        AuthAwareStubProtocol.reset()
        AuthAwareStubProtocol.script = { _ in (401, AuthAwareStubProtocol.errorBody) }
        let api = VenueAPI(
            baseURL: Self.engine,
            session: AuthAwareStubProtocol.makeSession(),
            tokenProvider: { "expired-token" },
            tokenRefresher: { nil }
        )

        await #expect(throws: VenueAPIError.authenticationRequired) {
            try await api.submitObservation(venueId: "v1", submittedBy: "device-1", answers: answers)
        }
        #expect(AuthAwareStubProtocol.requests.count == 1)
    }

    /// Signed-out 401s are NOT remapped to `.authenticationRequired` — the
    /// ticket's explicit "signed-out behaviour unchanged" scope guard. No
    /// refresh is even attempted (there is nothing to refresh).
    @Test func signedOutFourOhOneStaysPlainHTTPError() async throws {
        AuthAwareStubProtocol.reset()
        AuthAwareStubProtocol.script = { _ in (401, AuthAwareStubProtocol.errorBody) }
        let api = VenueAPI(
            baseURL: Self.engine,
            session: AuthAwareStubProtocol.makeSession(),
            tokenProvider: { nil },
            tokenRefresher: { Issue.record("refresher should not run when signed out"); return nil }
        )

        await #expect(throws: VenueAPIError.http(statusCode: 401)) {
            try await api.submitObservation(venueId: "v1", submittedBy: "device-1", answers: answers)
        }
        #expect(AuthAwareStubProtocol.requests.count == 1)
    }
}

/// Scripts a response per request (keyed however the test likes — usually
/// the `Authorization` header value), so one suite can pin both the
/// refresh-and-retry success path and the give-up path without a shared
/// call counter. Never registered globally.
final class AuthAwareStubProtocol: URLProtocol {
    struct Recorded: Sendable {
        let method: String
        let url: URL
        let body: Data?
        let headers: [String: String]
        var path: String { url.path }
        func headerValue(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    static let errorBody = try! JSONSerialization.data(withJSONObject: ["error": "unauthorized"])

    /// Always answers with the real fixture-backed 201, ignoring
    /// `Authorization` entirely — `EngineFixtures.respond` already knows how
    /// to shape a correctly-decodable `ObservationResponse` for these two
    /// routes; only the auth-injecting tests need a different script.
    static let alwaysSucceed: @Sendable (Recorded) -> (Int, Data) = { succeed($0) }

    static func succeed(_ request: Recorded) -> (Int, Data) {
        EngineFixtures.respond(to: RecordingURLProtocol.Recorded(
            method: request.method, url: request.url, body: request.body, headers: request.headers
        ))
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [Recorded] = []
    nonisolated(unsafe) static var script: (@Sendable (Recorded) -> (Int, Data))?

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        recorded = []
        script = nil
    }

    static var requests: [Recorded] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthAwareStubProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let entry = Recorded(
            method: request.httpMethod ?? "GET",
            url: request.url!,
            body: request.httpBody ?? Self.drain(request.httpBodyStream),
            headers: request.allHTTPHeaderFields ?? [:]
        )
        Self.lock.lock()
        Self.recorded.append(entry)
        let respond = Self.script
        Self.lock.unlock()

        let (status, data) = respond?(entry) ?? (404, Self.errorBody)
        let response = HTTPURLResponse(
            url: entry.url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// `URLSession` can hand a POST body to `URLProtocol` as a stream rather
    /// than `httpBody` (same reason `RecordingURLProtocol`/
    /// `ObservationRecordingProtocol` both drain it) — without this,
    /// `EngineFixtures.respond`'s `submittedBy` check sees an empty body and
    /// answers 401 regardless of what the test script wants.
    private static func drain(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
