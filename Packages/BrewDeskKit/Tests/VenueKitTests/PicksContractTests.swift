import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import VenueKit

/// Bamware Picks contract (bamware-ai#301): `Venue.pick`, `PicksResponse`,
/// `VenueAPI.fetchPicks` and the fixture service. The JSON below was
/// captured from the engine branch that adds the feature (claim `detail`
/// strings and the street address removed), so these are the engine's real
/// shapes, not a hand-written guess at them.
@Suite struct PicksContractTests {
    // MARK: Fixtures

    /// `GET /v1/venues/:id` → `venue`, for a venue that IS a pick.
    static let pickedVenueJSON = #"""
    {"id":"osm-node-10717839800","name":"Moshava Coffee","lat":40.7332791,"lng":-73.9985251,"neighborhood":"Greenwich Village","borough":"Manhattan","hoursRaw":"Tu-Fr 10:00-16:00","vertical":"cafe","venueType":"cafe","attributes":{"wifi":{"value":"ok","source":"estimate","confidence":0.3,"observedAt":"2026-09-16"},"outlets":{"value":"some","source":"estimate","confidence":0.3,"observedAt":"2026-09-16"},"laptopPolicy":{"value":"area_limited","timeWindow":"upstairs only; wifi 2-hour ticket","source":"curated","confidence":0.75,"observedAt":"2026-09-16"},"noise":{"value":"quiet","source":"estimate","confidence":0.3,"observedAt":"2026-09-16"},"seating":{"value":"some","source":"curated","confidence":0.75,"observedAt":"2026-09-16"},"outdoorSeating":{"value":"unknown","source":"estimate","confidence":0,"observedAt":"2026-08-01"}},"vibeTags":["two floors","study cafe","laptop upstairs"],"workScore":87,"lastVerified":"2026-09-16","links":{"osm":"https://www.openstreetmap.org/node/10717839800"},"tier":"researched","discoverySources":["fsq_os","overture"],"scoreDisplay":87,"scoreCoverage":{"known":2,"of":5,"weight":0.6,"attributes":["laptopPolicy","seating"]},"scoreConfidence":"low","pick":{"rank":1,"blurb":"Two floors. I take the laptop upstairs to the tables and couches; downstairs stays social and laptop-free.","visitedAt":"2026-10-27"}}
    """#

    /// `GET /v1/picks`, the whole body.
    static let picksJSON = #"""
    {"updatedAt":"2026-11-24","curator":"Bamware","picks":[{"rank":1,"blurb":"Two floors. I take the laptop upstairs to the tables and couches; downstairs stays social and laptop-free.","visitedAt":"2026-10-27","venue":{"id":"osm-node-10717839800","name":"Moshava Coffee","lat":40.7332791,"lng":-73.9985251,"workScore":87,"scoreDisplay":87,"scoreConfidence":"low","evidence":"researched","sourceCount":4,"neighborhood":"Greenwich Village","venueType":"cafe","scoreCoverage":{"known":2,"of":5,"weight":0.6,"attributes":["laptopPolicy","seating"]}}}]}
    """#

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    /// The same venue JSON with one top-level key removed or replaced.
    private func venueJSON(replacingPickWith replacement: String?) throws -> String {
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(Self.pickedVenueJSON.utf8)) as? [String: Any]
        )
        object.removeValue(forKey: "pick")
        var text = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        if let replacement {
            text = String(text.dropLast()) + ",\"pick\":\(replacement)}"
        }
        return text
    }

    // MARK: Venue.pick

    @Test func venueDecodesItsPick() throws {
        let venue = try decode(Venue.self, Self.pickedVenueJSON)
        #expect(venue.pick == VenuePick(
            rank: 1,
            blurb: "Two floors. I take the laptop upstairs to the tables and couches; downstairs stays social and laptop-free.",
            visitedAt: "2026-10-27"
        ))
        // The pick sits beside the score and changes nothing about it.
        #expect(venue.workScore == 87)
        #expect(venue.displayScore == 87)
        #expect(venue.scoreCoverage?.known == 2)
    }

    @Test func venueWithoutPickDecodesExactlyAsBefore() throws {
        // An engine that predates the feature, and every non-pick venue on
        // one that has it: the key is simply not there.
        let venue = try decode(Venue.self, try venueJSON(replacingPickWith: nil))
        #expect(venue.pick == nil)
        #expect(venue.name == "Moshava Coffee")
        #expect(venue.displayScore == 87)
    }

    @Test(arguments: [
        "null",
        "\"yes\"",
        "{}",
        "{\"rank\":\"one\",\"blurb\":\"x\",\"visitedAt\":\"2026-10-27\"}",
        "{\"rank\":1}",
        "[1,2,3]",
    ])
    func malformedPickNeverFailsTheVenue(replacement: String) throws {
        let venue = try decode(Venue.self, try venueJSON(replacingPickWith: replacement))
        #expect(venue.pick == nil)
        #expect(venue.id == "osm-node-10717839800")
        #expect(venue.workScore == 87)
    }

    @Test func pickDoesNotChangeAnyScoreField() throws {
        let with = try decode(Venue.self, Self.pickedVenueJSON)
        let without = try decode(Venue.self, try venueJSON(replacingPickWith: nil))
        #expect(with.workScore == without.workScore)
        #expect(with.scoreDisplay == without.scoreDisplay)
        #expect(with.displayScore == without.displayScore)
        #expect(with.isRated == without.isRated)
        #expect(with.scoreCoverage == without.scoreCoverage)
        #expect(with.scoreConfidence == without.scoreConfidence)
        #expect(with.scoreTier == without.scoreTier)
        #expect(with.settingPick(nil) == without)
    }

    @Test func pickSurvivesAnEncodeDecodeRoundTrip() throws {
        let venue = try decode(Venue.self, Self.pickedVenueJSON)
        let again = try JSONDecoder().decode(Venue.self, from: JSONEncoder().encode(venue))
        #expect(again == venue)
        #expect(again.pick?.rank == 1)

        // And a venue without one does not grow a `pick` key when re-encoded.
        let plain = venue.settingPick(nil)
        let encoded = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!encoded.contains("\"pick\""))
    }

    @Test func aListMixingPicksAndOthersDecodes() throws {
        let plain = try venueJSON(replacingPickWith: nil)
        let json = "{\"count\":2,\"venues\":[\(Self.pickedVenueJSON),\(plain)]}"
        let response = try decode(VenueListResponse.self, json)
        #expect(response.venues.map { $0.pick?.rank } == [1, nil])
    }

    // MARK: PicksResponse

    @Test func decodesTheEnginePicksBody() throws {
        let response = try decode(PicksResponse.self, Self.picksJSON)
        #expect(response.updatedAt == "2026-11-24")
        #expect(response.curator == "Bamware")
        #expect(response.picks.count == 1)
        let pick = try #require(response.picks.first)
        #expect(pick.rank == 1)
        #expect(pick.visitedAt == "2026-10-27")
        #expect(pick.blurb.hasPrefix("Two floors."))
        #expect(pick.venue.id == "osm-node-10717839800")
        #expect(pick.venue.name == "Moshava Coffee")
        #expect(pick.venue.neighborhood == "Greenwich Village")
        #expect(pick.venue.typeBadge == .cafe)
        #expect(pick.venue.displayScore == 87)
        #expect(pick.venue.scoreCoverage?.of == 5)
        #expect(pick.label == VenuePick(rank: 1, blurb: pick.blurb, visitedAt: "2026-10-27"))
    }

    @Test func emptyListDecodes() throws {
        // The engine's "no list" answer carries neither date nor curator.
        let response = try decode(PicksResponse.self, #"{"picks":[]}"#)
        #expect(response.picks.isEmpty)
        #expect(response.updatedAt == nil)
        #expect(response.curator == nil)
    }

    @Test(arguments: ["{}", #"{"picks":null}"#, #"{"picks":"none"}"#, #"{"updatedAt":7,"picks":[]}"#])
    func oddBodiesDecodeAsNoPicks(json: String) throws {
        let response = try decode(PicksResponse.self, json)
        #expect(response.picks.isEmpty)
        #expect(response.updatedAt == nil)
    }

    @Test func sortsByRankWhateverOrderArrives() throws {
        let rows = [3, 1, 10, 2].map { rank in
            #"{"rank":\#(rank),"blurb":"Line \#(rank).","visitedAt":"2026-10-27","venue":{"id":"v\#(rank)","name":"Cafe \#(rank)"}}"#
        }
        let response = try decode(PicksResponse.self, "{\"picks\":[\(rows.joined(separator: ","))]}")
        #expect(response.picks.map(\.rank) == [1, 2, 3, 10])
    }

    @Test func oneBadRowDoesNotHideTheOthers() throws {
        let json = #"""
        {"updatedAt":"2026-11-24","picks":[
          {"rank":1,"blurb":"Good.","visitedAt":"2026-10-27","venue":{"id":"a","name":"A"}},
          {"rank":2,"visitedAt":"2026-10-27","venue":{"id":"no-blurb","name":"B"}},
          {"rank":3,"blurb":"No venue.","visitedAt":"2026-10-27"},
          {"rank":4,"blurb":"   ","visitedAt":"2026-10-27","venue":{"id":"blank","name":"C"}},
          {"rank":0,"blurb":"Rank zero.","visitedAt":"2026-10-27","venue":{"id":"zero","name":"D"}},
          {"rank":5,"blurb":"Same venue again.","visitedAt":"2026-10-27","venue":{"id":"a","name":"A"}},
          "not an object",
          {"rank":6,"blurb":"Also good.","visitedAt":"2026-10-27","venue":{"id":"f","name":"F"}}
        ]}
        """#
        let response = try decode(PicksResponse.self, json)
        #expect(response.picks.map(\.venue.id) == ["a", "f"])
        #expect(response.picks.map(\.rank) == [1, 6])
    }

    // MARK: PickVenue score rules

    private func pickVenue(_ extra: String) throws -> PickVenue {
        try decode(PickVenue.self, "{\"id\":\"v\",\"name\":\"V\"\(extra)}")
    }

    @Test func explicitNullScoreIsNotRatedAndNeverFallsBackToWorkScore() throws {
        let venue = try pickVenue(#","workScore":52,"scoreDisplay":null,"evidence":"researched""#)
        #expect(venue.scoreDisplay == .notRated)
        #expect(venue.displayScore == nil)
    }

    @Test func numericScoreDisplayWins() throws {
        let venue = try pickVenue(#","workScore":40,"scoreDisplay":87"#)
        #expect(venue.displayScore == 87)
    }

    @Test func withoutScoreDisplayTheNumberNeedsRealEvidence() throws {
        #expect(try pickVenue(#","workScore":71,"evidence":"researched""#).displayScore == 71)
        #expect(try pickVenue(#","workScore":71,"evidence":"partial""#).displayScore == 71)
        #expect(try pickVenue(#","workScore":40,"evidence":"none""#).displayScore == nil)
        #expect(try pickVenue(#","workScore":40"#).displayScore == nil)
        #expect(try pickVenue("").displayScore == nil)
    }

    @Test func minimalVenueDecodesAndWrongTypesAreIgnored() throws {
        let venue = try pickVenue(#","neighborhood":7,"venueType":false,"scoreCoverage":"lots","workScore":"high""#)
        #expect(venue.neighborhood == nil)
        #expect(venue.venueType == nil)
        #expect(venue.typeBadge == .unknown)
        #expect(venue.scoreCoverage == nil)
        #expect(venue.workScore == nil)
    }

    // MARK: VenueAPI.fetchPicks

    @Test func olderEngineAnswers404AndFetchPicksThrowsIt() async {
        // An engine deployed before the feature has no such route.
        let api = VenueAPI(baseURL: URL(string: "https://picks-missing.test")!, session: PicksStubProtocol.makeSession())
        await #expect(throws: VenueAPIError.http(statusCode: 404)) {
            _ = try await api.fetchPicks()
        }
    }

    @Test func fetchPicksGetsTheRouteAndDecodesTheBody() async throws {
        let api = VenueAPI(baseURL: URL(string: "https://picks-ok.test")!, session: PicksStubProtocol.makeSession())
        let response = try await api.fetchPicks()
        #expect(response.picks.map(\.venue.name) == ["Moshava Coffee"])
        #expect(response.updatedAt == "2026-11-24")
    }

    @Test func aBodyThatIsNotJSONIsADecodingError() async {
        let api = VenueAPI(baseURL: URL(string: "https://picks-garbage.test")!, session: PicksStubProtocol.makeSession())
        await #expect(throws: VenueAPIError.decoding) {
            _ = try await api.fetchPicks()
        }
    }

    // MARK: ScenarioVenueService fixtures

    @Test func onePickScenarioServesOnePickAndBadgesOneVenue() async throws {
        let service = ScenarioVenueService(scenario: .onePick)
        let response = try await service.fetchPicks()
        #expect(response.picks.count == 1)
        #expect(response.picks.first?.venue.id == "fixture-roasters")
        #expect(response.updatedAt == "2026-11-24")

        let venues = try await service.fetchVenues(VenueQuery())
        #expect(venues.filter { $0.pick != nil }.map(\.id) == ["fixture-roasters"])
        #expect(try await service.fetchVenue(id: "fixture-roasters").pick?.rank == 1)
        #expect(try await service.fetchVenue(id: "fixture-corner").pick == nil)
        // Same venues, same scores as the plain fixture set.
        #expect(venues.map { $0.settingPick(nil) } == ScenarioVenueService.fixtureVenues)
    }

    @Test func tenPicksScenarioServesTenRankedFixtures() async throws {
        let service = ScenarioVenueService(scenario: .tenPicks)
        let response = try await service.fetchPicks()
        #expect(response.picks.map(\.rank) == Array(1...10))
        // Screenshots of this state must never pass for a real list.
        #expect(response.picks.allSatisfy { $0.venue.name.hasPrefix("Fixture ") })
        #expect(response.picks.allSatisfy { $0.blurb.hasPrefix("Fixture line") })
        #expect(response.picks.allSatisfy { $0.blurb.count <= 140 })
        #expect(response.picks.map(\.blurb.count).max() == 140)
        // The uneven cases the layout has to survive.
        #expect(response.picks[2].venue.displayScore == nil)
        #expect(response.picks[4].venue.typeBadge == .library)
        #expect(Set(response.picks.map(\.venue.id)).count == 10)

        for pick in response.picks {
            let venue = try await service.fetchVenue(id: pick.venue.id)
            #expect(venue.pick == pick.label)
            #expect(venue.displayScore == pick.venue.displayScore)
        }
    }

    @Test func scenariosThatPredatePicksServeNone() async throws {
        for scenario in ScenarioVenueService.Scenario.allCases where scenario != .onePick && scenario != .tenPicks {
            let service = ScenarioVenueService(scenario: scenario)
            switch scenario {
            case .engineDown, .offline:
                await #expect(throws: (any Error).self) { _ = try await service.fetchPicks() }
            default:
                #expect(try await service.fetchPicks().picks.isEmpty, "\(scenario)")
            }
        }
        #expect(ScenarioVenueService.fixtureVenues.allSatisfy { $0.pick == nil })
    }
}

/// Answers `/v1/picks` by host, so the stub needs no shared mutable state.
private final class PicksStubProtocol: URLProtocol {
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PicksStubProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let isPicks = request.httpMethod == "GET" && url.path == "/v1/picks"
        let body: String = switch (isPicks, url.host) {
        case (true, "picks-ok.test"): PicksContractTests.picksJSON
        case (true, "picks-garbage.test"): "<html>gateway</html>"
        default: #"{"error":"not_found"}"#
        }
        let status = body.hasPrefix(#"{"error""#) ? 404 : 200
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
