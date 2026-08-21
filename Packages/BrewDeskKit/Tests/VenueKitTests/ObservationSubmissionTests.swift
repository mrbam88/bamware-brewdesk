import Foundation
import Testing
@testable import VenueKit

/// Network-level contract tests for `POST /v1/venues/:id/observations`
/// (brewdesk#47, venue-engine PR #26) plus the ScenarioVenueService
/// stand-in's degradation contract — the UI tests lean on these being exact.
@Suite(.serialized) struct ObservationSubmissionTests {
    static let engine = URL(string: "https://venuekit-ashen.vercel.app")!

    private func api() -> VenueAPI {
        ObservationRecordingProtocol.reset()
        return VenueAPI(baseURL: Self.engine, session: ObservationRecordingProtocol.makeSession())
    }

    private var answers: ObservationAnswers {
        ObservationAnswers(
            laptopFriendlyToday: .mixed,
            seatsAvailable: .few,
            outletsWorking: .noneAvailable,
            noise: .quiet
        )
    }

    // MARK: VenueAPI wire contract

    @Test func submitPostsTheExactContractBody() async throws {
        let venue = try await api().submitObservation(
            venueId: "curated-devocin",
            submittedBy: "device-test-1",
            answers: answers
        )
        #expect(!venue.id.isEmpty)

        let request = try #require(ObservationRecordingProtocol.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/v1/venues/curated-devocin/observations")

        // Exactly the two top-level keys the strict schema accepts — any
        // extra key (i.e. any free-text smuggling) would be a 400.
        #expect(request.bodyKeys == ["submittedBy", "answers"])

        let body = try #require(request.body)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["submittedBy"] as? String == "device-test-1")
        let answersObject = try #require(object["answers"] as? [String: Any])
        #expect(Set(answersObject.keys) == [
            "laptopFriendlyToday", "seatsAvailable", "outletsWorking", "noise",
        ])
        #expect(answersObject["laptopFriendlyToday"] as? String == "mixed")
        #expect(answersObject["seatsAvailable"] as? String == "few")
        #expect(answersObject["outletsWorking"] as? String == "none")
        #expect(answersObject["noise"] as? String == "quiet")
        // Every answer value is a String from the closed enum vocabulary —
        // no free text can exist anywhere in the payload.
        #expect(answersObject.values.allSatisfy { $0 is String })
    }

    @Test func emptySubmitterSurfacesTheEngine401() async throws {
        await #expect(throws: VenueAPIError.http(statusCode: 401)) {
            try await api().submitObservation(
                venueId: "curated-devocin",
                submittedBy: "   ",
                answers: answers
            )
        }
    }

    /// Same privacy bar as PrivacyRequestAuditTests: the observation submit
    /// reaches only the engine host and carries no coordinate under any
    /// plausible key.
    @Test func submitCarriesNoCoordinatesAndOnlyTalksToTheEngine() async throws {
        _ = try await api().submitObservation(
            venueId: "curated-devocin",
            submittedBy: "device-test-2",
            answers: answers
        )
        let request = try #require(ObservationRecordingProtocol.requests.first)
        #expect(request.host == "venuekit-ashen.vercel.app")
        #expect(request.queryNames.isEmpty)
        let coordinateKeys: Set<String> = [
            "lat", "lng", "lon", "latitude", "longitude", "ll", "location",
            "coords", "coord", "geo", "position", "center",
        ]
        #expect(request.bodyKeys.intersection(coordinateKeys).isEmpty)
    }

    // MARK: ScenarioVenueService stand-in contract

    @Test func scenarioEngineDownThrows500() async {
        let service = ScenarioVenueService(scenario: .engineDown)
        await #expect(throws: VenueAPIError.http(statusCode: 500)) {
            try await service.submitObservation(
                venueId: "fixture-roasters", submittedBy: "t", answers: answers
            )
        }
    }

    @Test func scenarioOfflineThrowsNotConnected() async {
        let service = ScenarioVenueService(scenario: .offline)
        await #expect(throws: URLError(.notConnectedToInternet)) {
            try await service.submitObservation(
                venueId: "fixture-roasters", submittedBy: "t", answers: answers
            )
        }
    }

    @Test func scenarioFixtureOKReturnsTheMatchingVenue() async throws {
        let service = ScenarioVenueService(scenario: .fixtureOK)
        let venue = try await service.submitObservation(
            venueId: "fixture-corner", submittedBy: "t", answers: answers
        )
        #expect(venue.id == "fixture-corner")
    }

    /// Snapshot-seeded launches submit against non-fixture ids; the stand-in
    /// must stay lenient (the form ignores the returned venue).
    @Test func scenarioFixtureOKIsLenientOnUnknownIds() async throws {
        let service = ScenarioVenueService(scenario: .fixtureOK)
        let venue = try await service.submitObservation(
            venueId: "snapshot-unknown", submittedBy: "t", answers: answers
        )
        #expect(venue.id == "fixture-roasters")
    }

    /// The retry path: first submit fails, the retry succeeds — and the
    /// observation counter is independent of the venue-fetch counter, so a
    /// list fetch cannot consume the form's scripted failure.
    @Test func scenarioOfflineThenRecoversFailsOnlyTheFirstSubmit() async throws {
        let service = ScenarioVenueService(scenario: .offlineThenRecovers)

        // Venue fetch consumes ITS first failure…
        await #expect(throws: URLError(.notConnectedToInternet)) {
            try await service.fetchVenues(VenueQuery(limit: 10))
        }
        _ = try await service.fetchVenues(VenueQuery(limit: 10))

        // …and the first observation submit still fails, then recovers.
        await #expect(throws: URLError(.notConnectedToInternet)) {
            try await service.submitObservation(
                venueId: "fixture-roasters", submittedBy: "t", answers: answers
            )
        }
        let venue = try await service.submitObservation(
            venueId: "fixture-roasters", submittedBy: "t", answers: answers
        )
        #expect(venue.id == "fixture-roasters")
    }
}

/// This suite's own recorder. `RecordingURLProtocol`'s request log is a
/// process-wide static owned by `PrivacyRequestAuditTests` (its counts assume
/// it is the only writer, and suites run in parallel) — so this suite records
/// into its own class-scoped log and only shares the pure
/// `EngineFixtures.respond` contract.
final class ObservationRecordingProtocol: URLProtocol {
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
        config.protocolClasses = [ObservationRecordingProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? Self.drain(request.httpBodyStream)
        let entry = RecordingURLProtocol.Recorded(
            method: request.httpMethod ?? "GET",
            url: request.url!,
            body: body
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
