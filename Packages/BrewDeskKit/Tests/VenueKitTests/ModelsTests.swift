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
}
