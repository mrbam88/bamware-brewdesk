import Foundation
import Testing
@testable import VenueKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `POST /v1/chat` contract (bamware-brewdesk#247 ↔ venue-engine#218):
/// response/health decoding, request shape, bearer + single-refresh retry,
/// and every status → `ChatError` mapping the contract names. Own stub
/// protocol (never registered globally) so the suite can run in parallel
/// with `CommunityAuthTests`.
@Suite(.serialized) struct ChatContractTests {
    static let engine = URL(string: "https://venuekit-ashen.vercel.app")!

    // MARK: - Decoding

    @Test func decodesChatResponseWithRealVenueShape() throws {
        let venueJSON = try JSONEncoder().encode(ScenarioVenueService.fixtureVenues[0])
        let venueObject = try JSONSerialization.jsonObject(with: venueJSON) as! [String: Any]
        var withDistance = venueObject
        withDistance["distance_m"] = 640
        let body = try JSONSerialization.data(withJSONObject: [
            "reply": "Fixture Roasters is your best bet.",
            "venues": [withDistance],
            "meta": ["model": "gpt-test", "turnsLeftToday": 7]
        ])

        let response = try JSONDecoder().decode(ChatResponse.self, from: body)

        #expect(response.reply == "Fixture Roasters is your best bet.")
        #expect(response.venues.count == 1)
        #expect(response.venues[0].id == "fixture-roasters")
        #expect(response.venues[0].distanceM == 640)
        #expect(response.meta.model == "gpt-test")
        #expect(response.meta.turnsLeftToday == 7)
    }

    @Test func healthDecodesFeaturesWhenPresent() throws {
        let body = Data(#"{"ok":true,"venueCount":3,"seededAt":"2026-08-01T00:00:00Z","features":{"chat":true}}"#.utf8)
        let health = try JSONDecoder().decode(HealthResponse.self, from: body)
        #expect(health.features?.chat == true)
    }

    @Test func healthWithoutFeaturesStillDecodes() throws {
        let body = Data(#"{"ok":true,"venueCount":3,"seededAt":"2026-08-01T00:00:00Z"}"#.utf8)
        let health = try JSONDecoder().decode(HealthResponse.self, from: body)
        #expect(health.features == nil)
    }

    @Test func healthWithEmptyFeaturesObjectDefaultsChatOff() throws {
        let body = Data(#"{"ok":true,"venueCount":3,"seededAt":"2026-08-01T00:00:00Z","features":{}}"#.utf8)
        let health = try JSONDecoder().decode(HealthResponse.self, from: body)
        #expect(health.features?.chat == false)
    }

    @Test func requestEncodesContractKeys() throws {
        let request = ChatRequest(
            messages: [
                ChatMessage(role: .assistant, content: "Hi"),
                ChatMessage(role: .user, content: "Quiet spot?")
            ],
            location: ChatLocation(lat: 40.7365, lng: -73.9905)
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        let messages = object["messages"] as! [[String: Any]]
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "assistant")
        #expect(messages[1]["role"] as? String == "user")
        #expect(messages[1]["content"] as? String == "Quiet spot?")
        let location = object["location"] as! [String: Any]
        #expect(location["lat"] as? Double == 40.7365)
        #expect(location["lng"] as? Double == -73.9905)
    }

    @Test func requestOmitsLocationKeyWhenNil() throws {
        let request = ChatRequest(messages: [ChatMessage(role: .user, content: "Hi")])
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        #expect(object["location"] == nil)
    }

    // MARK: - sendChat

    private func successBody() throws -> Data {
        let venue = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(ScenarioVenueService.fixtureVenues[0])
        )
        return try JSONSerialization.data(withJSONObject: [
            "reply": "Go to Fixture Roasters.",
            "venues": [venue],
            "meta": ["model": "fixture", "turnsLeftToday": 3]
        ])
    }

    private func api(
        tokenProvider: @escaping @Sendable () async -> String?,
        tokenRefresher: @escaping @Sendable () async -> String? = { nil }
    ) -> VenueAPI {
        VenueAPI(
            baseURL: Self.engine,
            session: ChatStubProtocol.makeSession(),
            tokenProvider: tokenProvider,
            tokenRefresher: tokenRefresher
        )
    }

    private var oneUserTurn: ChatRequest {
        ChatRequest(messages: [ChatMessage(role: .user, content: "Quiet with outlets near me")])
    }

    @Test func postsToChatPathWithBearerAndJSONBody() async throws {
        ChatStubProtocol.reset()
        let success = try successBody()
        ChatStubProtocol.script = { _ in (200, success) }

        let response = try await api(tokenProvider: { "good-token" }).sendChat(oneUserTurn)

        #expect(response.reply == "Go to Fixture Roasters.")
        #expect(response.venues.map(\.id) == ["fixture-roasters"])
        #expect(response.meta.turnsLeftToday == 3)
        let requests = ChatStubProtocol.requests
        #expect(requests.count == 1)
        #expect(requests[0].method == "POST")
        #expect(requests[0].path == "/v1/chat")
        #expect(requests[0].headerValue("Authorization") == "Bearer good-token")
        #expect(requests[0].headerValue("Content-Type") == "application/json")
        let body = try JSONSerialization.jsonObject(with: requests[0].body ?? Data()) as? [String: Any]
        #expect((body?["messages"] as? [[String: Any]])?.count == 1)
    }

    @Test func fourOhOneRefreshesOnceThenSucceeds() async throws {
        ChatStubProtocol.reset()
        let success = try successBody()
        ChatStubProtocol.script = { request in
            request.headerValue("Authorization") == "Bearer fresh" ? (200, success) : (401, ChatStubProtocol.unauthorizedBody)
        }

        let response = try await api(tokenProvider: { "stale" }, tokenRefresher: { "fresh" }).sendChat(oneUserTurn)

        #expect(response.meta.turnsLeftToday == 3)
        #expect(ChatStubProtocol.requests.count == 2)
    }

    @Test func fourOhOneTwiceIsSignInRequired() async throws {
        ChatStubProtocol.reset()
        ChatStubProtocol.script = { _ in (401, ChatStubProtocol.unauthorizedBody) }

        await #expect(throws: ChatError.signInRequired) {
            try await api(tokenProvider: { "stale" }, tokenRefresher: { "still-bad" }).sendChat(oneUserTurn)
        }
        #expect(ChatStubProtocol.requests.count == 2)
    }

    @Test func signedOutFourOhOneIsSignInRequiredWithoutRetry() async throws {
        ChatStubProtocol.reset()
        ChatStubProtocol.script = { _ in (401, ChatStubProtocol.unauthorizedBody) }

        await #expect(throws: ChatError.signInRequired) {
            try await api(tokenProvider: { nil }).sendChat(oneUserTurn)
        }
        #expect(ChatStubProtocol.requests.count == 1)
        #expect(ChatStubProtocol.requests[0].headerValue("Authorization") == nil)
    }

    @Test func fourTwentyNineIsDailyCapWithResetAt() async throws {
        ChatStubProtocol.reset()
        ChatStubProtocol.script = { _ in
            (429, Data(#"{"error":"chat_daily_cap","resetAt":"2026-10-29T04:00:00Z"}"#.utf8))
        }

        do {
            _ = try await api(tokenProvider: { "good" }).sendChat(oneUserTurn)
            Issue.record("expected dailyCap")
        } catch ChatError.dailyCap(let resetAt) {
            #expect(resetAt == ISO8601DateFormatter().date(from: "2026-10-29T04:00:00Z"))
        }
    }

    @Test func fiveOhThreeIsDisabled() async throws {
        ChatStubProtocol.reset()
        ChatStubProtocol.script = { _ in (503, Data(#"{"error":"chat_disabled"}"#.utf8)) }
        await #expect(throws: ChatError.disabled) {
            try await api(tokenProvider: { "good" }).sendChat(oneUserTurn)
        }
    }

    @Test func fiveOhTwoIsUpstream() async throws {
        ChatStubProtocol.reset()
        ChatStubProtocol.script = { _ in (502, Data(#"{"error":"chat_upstream"}"#.utf8)) }
        await #expect(throws: ChatError.upstream) {
            try await api(tokenProvider: { "good" }).sendChat(oneUserTurn)
        }
    }

    @Test func transportFailureIsOffline() async throws {
        ChatStubProtocol.reset()
        ChatStubProtocol.failWith = URLError(.notConnectedToInternet)
        await #expect(throws: ChatError.offline) {
            try await api(tokenProvider: { "good" }).sendChat(oneUserTurn)
        }
    }

    @Test func unnamedStatusStaysPlainHTTPError() async throws {
        ChatStubProtocol.reset()
        ChatStubProtocol.script = { _ in (500, Data(#"{"error":"boom"}"#.utf8)) }
        await #expect(throws: VenueAPIError.http(statusCode: 500)) {
            try await api(tokenProvider: { "good" }).sendChat(oneUserTurn)
        }
    }

    // MARK: - ScenarioChatClient

    @Test func fixtureScenarioAnswersWithRoastersAndReadingRoom() async throws {
        let response = try await ScenarioChatClient(scenario: .fixtureOK).sendChat(oneUserTurn)
        #expect(response.venues.map(\.name) == ["Fixture Roasters", "Fixture Reading Room"])
        #expect(response.reply == ScenarioChatClient.fixtureReply)
    }

    @Test func degradedScenariosThrowMatchingChatErrors() async throws {
        await #expect(throws: ChatError.upstream) {
            try await ScenarioChatClient(scenario: .engineDown).sendChat(oneUserTurn)
        }
        await #expect(throws: ChatError.offline) {
            try await ScenarioChatClient(scenario: .offline).sendChat(oneUserTurn)
        }
        let empty = try await ScenarioChatClient(scenario: .emptyVenues).sendChat(oneUserTurn)
        #expect(empty.venues.isEmpty)
        #expect(empty.reply == ScenarioChatClient.emptyReply)
    }
}

/// Scripted stub for `/v1/chat`: records every request, answers from
/// `script`, or fails the transport with `failWith`.
final class ChatStubProtocol: URLProtocol {
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

    static let unauthorizedBody = Data(#"{"error":"unauthorized"}"#.utf8)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [Recorded] = []
    nonisolated(unsafe) static var script: (@Sendable (Recorded) -> (Int, Data))?
    nonisolated(unsafe) static var failWith: URLError?

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        recorded = []
        script = nil
        failWith = nil
    }

    static var requests: [Recorded] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChatStubProtocol.self]
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
        let failure = Self.failWith
        Self.lock.unlock()

        if let failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let (status, data) = respond?(entry) ?? (404, Self.unauthorizedBody)
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
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
