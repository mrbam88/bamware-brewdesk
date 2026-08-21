import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import VenueKit

/// AuthAPI wire contract against bamware-auth-service (brewdesk#48), pinned
/// through a recording URL protocol — nothing reaches the network. The
/// companion server-side pins live in auth-service PR #6
/// (`brewdeskTenant.test.ts`).
///
/// Own recording class (not `RecordingURLProtocol`) so this suite's static
/// request log cannot race other suites — same isolation trick as
/// `ObservationRecordingProtocol`.
@Suite(.serialized) struct AuthAPITests {
    private let base = URL(string: "https://auth.test")!

    private func makeAPI() -> AuthAPI {
        AuthAPI(baseURL: base, session: AuthRecordingProtocol.makeSession())
    }

    init() {
        AuthRecordingProtocol.reset()
    }

    // MARK: - Register

    @Test func registerSendsTenantScopedBodyAndDecodesSession() async throws {
        let session = try await makeAPI().register(
            email: "new@bamware.com", password: "FlatWhite11!", name: "New Taster"
        )

        let request = try #require(AuthRecordingProtocol.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/auth/register")
        #expect(request.bodyKeys == ["email", "password", "name", "tenantId"])
        #expect(request.contains("bamware-brewdesk"))

        #expect(session.accessToken == "fixture-access")
        #expect(session.refreshToken == "fixture-refresh")
        #expect(session.user.email == "new@bamware.com")
        #expect(session.user.tenantId == "bamware-brewdesk")
    }

    @Test func registerMaps409ToEmailAlreadyRegistered() async {
        await #expect(throws: AuthAPIError.emailAlreadyRegistered) {
            _ = try await makeAPI().register(
                email: "taken@bamware.com", password: "FlatWhite11!", name: "Dup"
            )
        }
    }

    // MARK: - Sign in

    @Test func signInSendsTenantScopedBody() async throws {
        _ = try await makeAPI().signIn(email: "tester@bamware.com", password: "FlatWhite11!")

        let request = try #require(AuthRecordingProtocol.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/auth/login")
        #expect(request.bodyKeys == ["email", "password", "tenantId"])
        #expect(request.contains("bamware-brewdesk"))
    }

    @Test func signInMaps401ToInvalidCredentials() async {
        await #expect(throws: AuthAPIError.invalidCredentials) {
            _ = try await makeAPI().signIn(email: "tester@bamware.com", password: "WrongPass99!")
        }
    }

    // MARK: - Delete account (Apple 5.1.1(v))

    @Test func deleteAccountSendsBearerToken() async throws {
        try await makeAPI().deleteAccount(accessToken: "token-123")

        let request = try #require(AuthRecordingProtocol.requests.first)
        #expect(request.method == "DELETE")
        #expect(request.path == "/auth/account")
        #expect(request.headers["Authorization"] == "Bearer token-123")
        #expect(request.body == nil)
    }

    /// The ordered-deletion pattern depends on retries being safe: the server
    /// treats "already gone" as 404 and the client treats 404 as success.
    @Test func deleteAccountTreats404AsSuccess() async throws {
        try await makeAPI().deleteAccount(accessToken: "already-gone")
        #expect(AuthRecordingProtocol.requests.count == 1)
    }
}

/// Recording loader for AuthAPI tests: same shape as `RecordingURLProtocol`
/// but with its own static log, answering from `EngineFixtures` (which owns
/// the canned auth-service responses).
final class AuthRecordingProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [RecordingURLProtocol.Recorded] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        recorded = []
    }

    static var requests: [RecordingURLProtocol.Recorded] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthRecordingProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let entry = RecordingURLProtocol.Recorded(
            method: request.httpMethod ?? "GET",
            url: request.url!,
            body: request.httpBody ?? Self.drain(request.httpBodyStream),
            headers: request.allHTTPHeaderFields ?? [:]
        )
        Self.lock.lock()
        Self.recorded.append(entry)
        Self.lock.unlock()

        let (status, data) = EngineFixtures.respond(to: entry)
        let response = HTTPURLResponse(
            url: entry.url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

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
