import Foundation
import Testing
@testable import VenueKit

@Suite struct ModelsTests {
    private func loadFixture() throws -> VenueListResponse {
        let url = Bundle.module.url(forResource: "venues", withExtension: "json")!
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(VenueListResponse.self, from: data)
    }

    @Test func decodesVenueListFixture() throws {
        let response = try loadFixture()
        #expect(response.count == 2)
        #expect(response.venues.count == 2)

        let devocion = response.venues[0]
        #expect(devocion.name == "Devoción")
        #expect(devocion.distanceM == 640) // snake_case distance_m mapped
        #expect(devocion.attributes.wifi.mbpsRange == [50, 120])
        #expect(devocion.attributes.wifi.isEstimate == false)

        let random = response.venues[1]
        #expect(random.distanceM == nil)
        #expect(random.attributes.wifi.isEstimate)
        #expect(random.attributes.wifi.confidencePercent == 30)
    }

    @Test func scoreTiersBandCorrectly() {
        #expect(ScoreTier(score: 90) == .great)
        #expect(ScoreTier(score: 75) == .great)
        #expect(ScoreTier(score: 60) == .good)
        #expect(ScoreTier(score: 50) == .mixed)
        #expect(ScoreTier(score: 20) == .weak)
    }

    @Test func sourceLabelsAreHuman() {
        let claim = Claim(
            value: "fast", detail: nil, mbpsRange: nil, timeWindow: nil,
            source: "speed_test", confidence: 0.9, observedAt: "2026-08-03"
        )
        #expect(claim.sourceLabel == "measured in-app")
        #expect(claim.isMeasured)
    }

    // bd#180: "agent" used to fall through sourceLabel's `default: source`
    // and leak the raw wire value into the UI.
    @Test func agentSourceLabelIsPressResearch() {
        let claim = Claim(
            value: "fast", source: "agent", confidence: 0.6, observedAt: "2026-08-03"
        )
        #expect(claim.sourceLabel == "press research")
    }

    @Test func typedQuerySerializesToBackendContract() {
        let query = VenueQuery(
            lat: 40.73,
            lng: -73.99,
            radiusM: 2_500,
            wifiMinimum: .fast,
            outletMinimum: .some,
            laptopFriendlyOnly: true,
            neighborhood: "NoHo",
            search: "coffee",
            sort: .distance,
            limit: 100
        )
        let values = Dictionary(uniqueKeysWithValues: query.urlQueryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(values["wifi_min"] == "fast")
        #expect(values["outlets_min"] == "some")
        #expect(values["laptops"] == "friendly")
        #expect(values["sort"] == "distance")
        #expect(values["limit"] == "100")
        #expect(values["q"] == "coffee")
        // brewdesk#154: coordinates leave via the viewport header, not the URL.
        #expect(values["lat"] == nil)
        #expect(values["lng"] == nil)
        #expect(query.viewportHeaderValue == "\(40.73),\(-73.99)")
    }
}

/// `Venue.isObserved` (bd#159): mirrors bamware-venue-engine ve#64 — a venue
/// counts as observed only when at least one scored claim (wifi, outlets,
/// laptopPolicy, noise, seating) is not an `estimate` and has confidence
/// ≥ 0.4. Everything else (estimate-only, low-confidence-only) is the
/// engine's flat neutral fallback score, not a measurement.
@Suite struct VenueIsObservedTests {
    private static let observedAt = "2026-08-01T00:00:00Z"

    private static func claim(value: String = "fast", source: String, confidence: Double) -> Claim {
        Claim(value: value, source: source, confidence: confidence, observedAt: observedAt)
    }

    private static func venue(
        wifi: Claim,
        outlets: Claim? = nil,
        laptopPolicy: Claim? = nil,
        noise: Claim? = nil,
        seating: Claim? = nil
    ) -> Venue {
        let fallback = claim(source: "estimate", confidence: 0.2)
        return Venue(
            id: "v",
            name: "Test Venue",
            lat: 40.7,
            lng: -74.0,
            address: nil,
            neighborhood: "SoHo",
            borough: "Manhattan",
            hoursRaw: nil,
            vertical: "cafe",
            attributes: VenueAttributes(
                wifi: wifi,
                outlets: outlets ?? fallback,
                laptopPolicy: laptopPolicy ?? fallback,
                noise: noise ?? fallback,
                seating: seating
            ),
            vibeTags: [],
            workScore: 52,
            lastVerified: nil,
            distanceM: nil
        )
    }

    @Test func estimateOnlyVenueIsNotObserved() {
        let v = Self.venue(
            wifi: Self.claim(source: "estimate", confidence: 0.9),
            outlets: Self.claim(source: "estimate", confidence: 0.9),
            laptopPolicy: Self.claim(source: "estimate", confidence: 0.9),
            noise: Self.claim(source: "estimate", confidence: 0.9)
        )
        #expect(v.isObserved == false)
    }

    @Test func lowConfidenceVenueIsNotObserved() {
        // Real sources, but every one under the 0.4 floor.
        let v = Self.venue(
            wifi: Self.claim(source: "osm", confidence: 0.3),
            outlets: Self.claim(source: "curated", confidence: 0.1),
            laptopPolicy: Self.claim(source: "agent", confidence: 0.39),
            noise: Self.claim(source: "osm", confidence: 0.2)
        )
        #expect(v.isObserved == false)
    }

    @Test func oneCuratedClaimMakesItObserved() {
        // Everything else is a low-confidence estimate; one curated claim
        // at high confidence is enough.
        let v = Self.venue(
            wifi: Self.claim(source: "estimate", confidence: 0.2),
            outlets: Self.claim(source: "curated", confidence: 0.85)
        )
        #expect(v.isObserved)
    }

    @Test func osmWifiAtHalfConfidenceIsObserved() {
        // Not an estimate, and above the 0.4 floor — counts even though the
        // source is the OSM baseline tier, not curated/agent research.
        let v = Self.venue(wifi: Self.claim(source: "osm", confidence: 0.5))
        #expect(v.isObserved)
    }

    @Test func unknownValueNeverCountsAsObserved() {
        // A confident, non-estimate claim that says "unknown" is still no
        // observation — it must not earn the venue a printed score.
        let v = Self.venue(
            wifi: Self.claim(value: "unknown", source: "osm", confidence: 0.9),
            outlets: Self.claim(value: "unknown", source: "curated", confidence: 0.8)
        )
        #expect(v.isObserved == false)
    }

    @Test func exactlyAtTheConfidenceFloorIsObserved() {
        let v = Self.venue(wifi: Self.claim(source: "osm", confidence: 0.4))
        #expect(v.isObserved)
    }

    @Test func seatingAloneCanMakeItObserved() {
        // seating is optional and absent on v1 payloads — a real claim
        // there still counts toward isObserved like any other scored claim.
        let v = Self.venue(
            wifi: Self.claim(source: "estimate", confidence: 0.2),
            seating: Self.claim(source: "field_visit", confidence: 0.7)
        )
        #expect(v.isObserved)
    }

    @Test func absentSeatingNeverCountsAgainstObserved() {
        let v = Self.venue(wifi: Self.claim(source: "curated", confidence: 0.9), seating: nil)
        #expect(v.isObserved)
    }
}

/// `Venue.scoreDisplay`/`displayScore`/`isRated` (brewdesk#213): the server's
/// additive honest-score signal — a JSON number, an explicit JSON `null`, or
/// the key entirely absent (older server / metro outside the rollout) must
/// decode to three DISTINCT states, never collapsed to the same "nil".
@Suite struct ScoreDisplayTests {
    private static let observedAt = "2026-08-01T00:00:00Z"

    /// `isObserved` toggles which claim confidence/source the venue carries
    /// — lets every test below prove `scoreDisplay`, when present, wins
    /// over the `isObserved` heuristic in EITHER direction.
    private static func json(scoreDisplayField: String?, isObserved: Bool) -> String {
        let claimSource = isObserved ? "curated" : "estimate"
        let claimConfidence = isObserved ? 0.9 : 0.2
        let scoreDisplayKey = scoreDisplayField.map { ",\"scoreDisplay\":\($0)" } ?? ""
        return """
        {"id":"v1","name":"Spot","lat":40.7,"lng":-74.0,"address":null,
         "neighborhood":"SoHo","borough":"Manhattan","hoursRaw":null,"vertical":"cafe",
         "attributes":{
           "wifi":{"value":"fast","source":"\(claimSource)","confidence":\(claimConfidence),"observedAt":"\(observedAt)"},
           "outlets":{"value":"some","source":"\(claimSource)","confidence":\(claimConfidence),"observedAt":"\(observedAt)"},
           "laptopPolicy":{"value":"unrestricted","source":"\(claimSource)","confidence":\(claimConfidence),"observedAt":"\(observedAt)"},
           "noise":{"value":"moderate","source":"\(claimSource)","confidence":\(claimConfidence),"observedAt":"\(observedAt)"}
         },
         "vibeTags":[],"workScore":40,"lastVerified":null\(scoreDisplayKey)}
        """
    }

    private static func decode(_ json: String) throws -> Venue {
        try JSONDecoder().decode(Venue.self, from: Data(json.utf8))
    }

    // MARK: - Decoding: number / null / absent are three distinct states

    @Test func aNumberDecodesAsRated() throws {
        let venue = try Self.decode(Self.json(scoreDisplayField: "72", isObserved: true))
        #expect(venue.scoreDisplay == .rated(72))
        #expect(venue.isRated)
        #expect(venue.displayScore == 72)
    }

    @Test func explicitNullDecodesAsNotRatedNeverFallsBackToWorkScore() throws {
        // isObserved: true on purpose — an explicit server `null` must win
        // over the client-side heuristic, not just agree with it by luck.
        let venue = try Self.decode(Self.json(scoreDisplayField: "null", isObserved: true))
        #expect(venue.scoreDisplay == .notRated)
        #expect(venue.isRated == false)
        #expect(venue.displayScore == nil)
        #expect(venue.isObserved) // heuristic alone would have said "rated" — proves the override
    }

    @Test func absentKeyDecodesAsNotProvidedAndFallsBackToIsObserved() throws {
        let rated = try Self.decode(Self.json(scoreDisplayField: nil, isObserved: true))
        #expect(rated.scoreDisplay == .notProvided)
        #expect(rated.isRated)
        #expect(rated.displayScore == rated.workScore)

        let unrated = try Self.decode(Self.json(scoreDisplayField: nil, isObserved: false))
        #expect(unrated.scoreDisplay == .notProvided)
        #expect(unrated.isRated == false)
        #expect(unrated.displayScore == nil)
    }

    /// The exact ambiguity `container.contains(_:)` exists to resolve:
    /// absent and null must never collapse to the same `Venue` state.
    @Test func absentAndNullAreDistinctScoreDisplayStates() throws {
        let absent = try Self.decode(Self.json(scoreDisplayField: nil, isObserved: false))
        let null = try Self.decode(Self.json(scoreDisplayField: "null", isObserved: false))
        #expect(absent.scoreDisplay != null.scoreDisplay)
        #expect(absent.scoreDisplay == .notProvided)
        #expect(null.scoreDisplay == .notRated)
    }

    @Test func ratedNumberEqualsWorkScoreOnTheWireButComesFromScoreDisplay() throws {
        // Mirrors the real contract: for a rated café, scoreDisplay ==
        // workScore, but displayScore must read scoreDisplay, not workScore.
        let json = """
        {"id":"v1","name":"Spot","lat":40.7,"lng":-74.0,"address":null,
         "neighborhood":"SoHo","borough":"Manhattan","hoursRaw":null,"vertical":"cafe",
         "attributes":{
           "wifi":{"value":"fast","source":"curated","confidence":0.9,"observedAt":"\(Self.observedAt)"},
           "outlets":{"value":"some","source":"curated","confidence":0.9,"observedAt":"\(Self.observedAt)"},
           "laptopPolicy":{"value":"unrestricted","source":"curated","confidence":0.9,"observedAt":"\(Self.observedAt)"},
           "noise":{"value":"moderate","source":"curated","confidence":0.9,"observedAt":"\(Self.observedAt)"}
         },
         "vibeTags":[],"workScore":72,"lastVerified":null,"scoreDisplay":72}
        """
        let venue = try Self.decode(json)
        #expect(venue.workScore == 72)
        #expect(venue.displayScore == 72)
    }

    // MARK: - Round trip (caches/snapshots must preserve all three states)

    @Test func allThreeScoreDisplayStatesRoundTripThroughCodable() throws {
        for scoreDisplay in [ScoreDisplay.notProvided, .notRated, .rated(64)] {
            let venue = ScoreDisplayTests.venue(scoreDisplay: scoreDisplay)
            let data = try JSONEncoder().encode(venue)
            let decoded = try JSONDecoder().decode(Venue.self, from: data)
            #expect(decoded == venue)
            #expect(decoded.scoreDisplay == scoreDisplay)
        }
    }

    @Test func notProvidedOmitsTheKeyOnEncodeRatherThanFabricatingNull() throws {
        let venue = ScoreDisplayTests.venue(scoreDisplay: .notProvided)
        let data = try JSONEncoder().encode(venue)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("scoreDisplay"))
    }

    @Test func notRatedEncodesARealJSONNull() throws {
        let venue = ScoreDisplayTests.venue(scoreDisplay: .notRated)
        let data = try JSONEncoder().encode(venue)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"scoreDisplay\":null"))
    }

    @Test func ratedEncodesTheNumber() throws {
        let venue = ScoreDisplayTests.venue(scoreDisplay: .rated(64))
        let data = try JSONEncoder().encode(venue)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"scoreDisplay\":64"))
    }

    private static func venue(scoreDisplay: ScoreDisplay) -> Venue {
        let claim = Claim(value: "fast", source: "curated", confidence: 0.8, observedAt: observedAt)
        return Venue(
            id: "v1",
            name: "Spot",
            lat: 40.7,
            lng: -74.0,
            address: nil,
            neighborhood: "SoHo",
            borough: "Manhattan",
            hoursRaw: nil,
            vertical: "cafe",
            attributes: VenueAttributes(wifi: claim, outlets: claim, laptopPolicy: claim, noise: claim),
            vibeTags: [],
            workScore: 64,
            lastVerified: nil,
            distanceM: nil,
            scoreDisplay: scoreDisplay
        )
    }
}

@Suite struct SchemaV2WireTests {
    @Test func v2WireNamesAreCamelCase() {
        let query = VenueQuery(seatingMinimum: .some, venueType: .park)
        let items = query.urlQueryItems
        #expect(items.contains(URLQueryItem(name: "minSeating", value: "some")))
        #expect(items.contains(URLQueryItem(name: "venueType", value: "park")))
    }

    @Test func venueDecodesWithAndWithoutV2Fields() throws {
        let base = """
        {"id":"v1","name":"Spot","lat":40.7,"lng":-74.0,"address":null,
         "neighborhood":"SoHo","borough":"Manhattan","hoursRaw":null,"vertical":"cafe",
         "attributes":{
           "wifi":{"value":"fast","source":"agent","confidence":0.8,"observedAt":"2026-08-15T00:00:00Z"},
           "outlets":{"value":"some","source":"agent","confidence":0.7,"observedAt":"2026-08-15T00:00:00Z"},
           "laptopPolicy":{"value":"unrestricted","source":"agent","confidence":0.7,"observedAt":"2026-08-15T00:00:00Z"},
           "noise":{"value":"moderate","source":"agent","confidence":0.6,"observedAt":"2026-08-15T00:00:00Z"}
         },
         "vibeTags":[],"workScore":80,"lastVerified":null}
        """
        let v1 = try JSONDecoder().decode(Venue.self, from: Data(base.utf8))
        #expect(v1.venueType == nil)
        #expect(v1.attributes.seating == nil)
        #expect(v1.email == nil) // optional-first (bd#56): absent decodes as nil

        let v2Json = base.replacingOccurrences(
            of: "\"vibeTags\":[],",
            with: """
            "vibeTags":[],"venueType":"library","email":"hello@spot.example",
            """
        ).replacingOccurrences(
            of: "\"noise\":",
            with: """
            "seating":{"value":"plenty","source":"site_visit","confidence":0.9,"observedAt":"2026-08-16T00:00:00Z"},
            "outdoorSeating":{"value":"yes","source":"agent","confidence":0.6,"observedAt":"2026-08-16T00:00:00Z"},
            "noise":
            """
        )
        let v2 = try JSONDecoder().decode(Venue.self, from: Data(v2Json.utf8))
        #expect(v2.venueType == "library")
        #expect(v2.attributes.seating?.value == "plenty")
        #expect(v2.attributes.outdoorSeating?.value == "yes")
        #expect(v2.email == "hello@spot.example")
    }

    // MARK: - News links (ve#103, bd#180)

    @Test func venueDecodesWithoutNewsAsNil() throws {
        let json = """
        {"id":"v1","name":"Spot","lat":40.7,"lng":-74.0,"address":null,
         "neighborhood":"SoHo","borough":"Manhattan","hoursRaw":null,"vertical":"cafe",
         "attributes":{
           "wifi":{"value":"fast","source":"agent","confidence":0.8,"observedAt":"2026-08-15T00:00:00Z"},
           "outlets":{"value":"some","source":"agent","confidence":0.7,"observedAt":"2026-08-15T00:00:00Z"},
           "laptopPolicy":{"value":"unrestricted","source":"agent","confidence":0.7,"observedAt":"2026-08-15T00:00:00Z"},
           "noise":{"value":"moderate","source":"agent","confidence":0.6,"observedAt":"2026-08-15T00:00:00Z"}
         },
         "vibeTags":[],"workScore":80,"lastVerified":null}
        """
        let venue = try JSONDecoder().decode(Venue.self, from: Data(json.utf8))
        #expect(venue.news == nil)
    }

    @Test func venueDecodesNewsLinksWhenPresent() throws {
        let json = """
        {"id":"v1","name":"Spot","lat":40.7,"lng":-74.0,"address":null,
         "neighborhood":"SoHo","borough":"Manhattan","hoursRaw":null,"vertical":"cafe",
         "attributes":{
           "wifi":{"value":"fast","source":"agent","confidence":0.8,"observedAt":"2026-08-15T00:00:00Z"},
           "outlets":{"value":"some","source":"agent","confidence":0.7,"observedAt":"2026-08-15T00:00:00Z"},
           "laptopPolicy":{"value":"unrestricted","source":"agent","confidence":0.7,"observedAt":"2026-08-15T00:00:00Z"},
           "noise":{"value":"moderate","source":"agent","confidence":0.6,"observedAt":"2026-08-15T00:00:00Z"}
         },
         "vibeTags":[],"workScore":80,"lastVerified":null,
         "news":[
           {"url":"https://www.theinfatuation.com/new-york/guides/coffee-shops-nyc-for-doing-work",
            "title":"The Best NYC Coffee Shops With Wifi For Getting Work Done",
            "sourceDomain":"theinfatuation.com",
            "observedAt":"2026-05-28",
            "tag":"news"},
           {"url":"https://fixture-gazette.example/spot",
            "sourceDomain":"fixture-gazette.example",
            "observedAt":"2026-06-01",
            "tag":"news"}
         ]}
        """
        let venue = try JSONDecoder().decode(Venue.self, from: Data(json.utf8))
        #expect(venue.news?.count == 2)
        #expect(venue.news?[0].sourceDomain == "theinfatuation.com")
        #expect(venue.news?[0].displayTitle == "The Best NYC Coffee Shops With Wifi For Getting Work Done")
        // No `title` on the second link — `displayTitle` falls back to nil,
        // the caller falls back to `sourceDomain`.
        #expect(venue.news?[1].title == nil)
        #expect(venue.news?[1].displayTitle == nil)
    }

    @Test func newsLinkDisplayTitleTrimsAndTreatsBlankAsAbsent() {
        #expect(NewsLink(url: "u", title: "  A Title \n", sourceDomain: "d", observedAt: "2026-01-01").displayTitle == "A Title")
        #expect(NewsLink(url: "u", title: "   ", sourceDomain: "d", observedAt: "2026-01-01").displayTitle == nil)
        #expect(NewsLink(url: "u", title: "", sourceDomain: "d", observedAt: "2026-01-01").displayTitle == nil)
        #expect(NewsLink(url: "u", sourceDomain: "d", observedAt: "2026-01-01").displayTitle == nil)
    }
}

@Suite struct VenuePhotoTests {
    @Test func decodesPhotosResponseAndResolvesRelativeURLs() throws {
        let json = """
        {"photos":[{"url":"/v1/venues/v1/photos/0/media","attribution":"Ada","attributionUri":"https://maps.google.com/ada","widthPx":800,"heightPx":600},
                   {"url":"https://elsewhere.example/x.jpg"}]}
        """
        let response = try JSONDecoder().decode(VenuePhotosResponse.self, from: Data(json.utf8))
        #expect(response.photos.count == 2)
        #expect(response.photos[0].attributionUri == "https://maps.google.com/ada")
        #expect(response.photos[1].attributionUri == nil)

        let base = URL(string: "https://venuekit-ashen.vercel.app")!
        #expect(VenueAPI.absolutePhotoURL(response.photos[0].url, base: base)
            == "https://venuekit-ashen.vercel.app/v1/venues/v1/photos/0/media")
        // Absolute URLs pass through untouched.
        #expect(VenueAPI.absolutePhotoURL(response.photos[1].url, base: base)
            == "https://elsewhere.example/x.jpg")
    }

    // MARK: - Contributor bylines (brewdesk#49)

    @Test func decodesContributorNameAndStaysAdditive() throws {
        let json = """
        {"photos":[{"url":"https://cdn.example/community.jpg","contributorName":"Ada L.","widthPx":1200,"heightPx":900},
                   {"url":"https://cdn.example/google.jpg","attribution":"Grace","attributionUri":"https://maps.google.com/grace"}]}
        """
        let response = try JSONDecoder().decode(VenuePhotosResponse.self, from: Data(json.utf8))
        let community = response.photos[0]
        #expect(community.contributorName == "Ada L.")
        #expect(community.communityByline == "Ada L.")
        #expect(community.attribution == nil)

        // Pre-#49 payload shape (no contributorName) decodes as a Google photo.
        let google = response.photos[1]
        #expect(google.contributorName == nil)
        #expect(google.communityByline == nil)
        #expect(google.attribution == "Grace")
    }

    @Test func communityBylineTrimsAndTreatsBlankAsAbsent() {
        #expect(VenuePhoto(url: "u", contributorName: "  Ada L. \n").communityByline == "Ada L.")
        #expect(VenuePhoto(url: "u", contributorName: "   ").communityByline == nil)
        #expect(VenuePhoto(url: "u", contributorName: "").communityByline == nil)
        #expect(VenuePhoto(url: "u").communityByline == nil)
    }

    @Test func contributorNameRoundTripsThroughCodable() throws {
        let photo = VenuePhoto(url: "https://cdn.example/c.jpg", contributorName: "Ada L.")
        let data = try JSONEncoder().encode(photo)
        #expect(try JSONDecoder().decode(VenuePhoto.self, from: data) == photo)
    }
}
