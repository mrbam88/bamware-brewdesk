import Foundation
import Testing
@testable import VenueKit

/// Privacy-claim verifier (brewdesk#29). Defends the App Privacy answer
/// "Data Not Collected" by recording every request `VenueAPI` issues and
/// proving, per flow, which host receives coordinates and which never can.
///
/// Facts these tests pin (see docs/PRIVACY-AUDIT.md):
/// - Coordinates travel ONLY as `lat`/`lng` on `GET {engine}/v1/venues`.
/// - With location denied the app queries the public Union Square anchor
///   (VenuesModel.coverageCenter*), never a device coordinate.
/// - With location granted, the app now always queries the real coordinate
///   (bd#108 removed the out-of-coverage rejection this suite used to test
///   at the wire level) — the coordinate still reaches only the engine, used
///   transiently to rank one response.
/// - Photo bytes come from a Google host, but those URLs carry no coordinates
///   and no identifiers; no other third-party host is ever contacted.
@Suite(.serialized) struct PrivacyRequestAuditTests {
    /// The Release `VenueAPI.defaultBaseURL`. Pinned literally so a future
    /// host change has to come through this suite.
    static let engine = URL(string: "https://venuekit-ashen.vercel.app")!
    static let engineHost = "venuekit-ashen.vercel.app"

    /// Union Square — VenuesModel.coverageCenterLat/Lng, the deterministic
    /// fallback used whenever Core Location has not supplied a coordinate.
    static let anchor = (lat: 40.7359, lng: -73.9911)

    /// Any query/body key that could plausibly carry a location.
    static let coordinateKeys: Set<String> = [
        "lat", "lng", "lon", "latitude", "longitude", "ll", "location",
        "coords", "coord", "geo", "position", "center",
    ]

    private func api() -> VenueAPI {
        RecordingURLProtocol.reset()
        return VenueAPI(baseURL: Self.engine, session: RecordingURLProtocol.makeSession())
    }

    private func coordinateNames(in request: RecordingURLProtocol.Recorded) -> Set<String> {
        let query = Set(request.queryNames).intersection(Self.coordinateKeys)
        let body = request.bodyKeys.intersection(Self.coordinateKeys)
        return query.union(body)
    }

    /// Every read flow the v1 UI exercises: map/list, stat strip, detail,
    /// photo strip, neighborhood chips.
    private func runReadFlows(_ api: VenueAPI, query: VenueQuery) async throws {
        _ = try await api.fetchVenues(query)
        _ = try await api.fetchHealth()
        _ = try await api.fetchVenue(id: "curated-devocin")
        _ = try await api.fetchPhotos(venueId: "curated-devocin")
        _ = try await api.fetchNeighborhoods()
    }

    // MARK: Location denied

    @Test func deniedFlowsSendOnlyTheCoverageAnchor() async throws {
        let api = api()
        // Exactly what VenuesModel.request emits when no location was granted.
        let denied = VenueQuery(lat: Self.anchor.lat, lng: Self.anchor.lng, radiusM: 2_500, sort: .workScore, limit: 100)
        try await runReadFlows(api, query: denied)

        let requests = RecordingURLProtocol.requests
        #expect(requests.count == 5)
        #expect(requests.allSatisfy { $0.host == Self.engineHost })

        for request in requests {
            let names = coordinateNames(in: request)
            if request.path == "/v1/venues" {
                #expect(names == ["lat", "lng"], "only lat/lng may carry a coordinate")
                #expect(request.queryValue("lat") == String(Self.anchor.lat))
                #expect(request.queryValue("lng") == String(Self.anchor.lng))
            } else {
                #expect(names.isEmpty, "\(request.path) must not carry coordinates")
            }
        }
    }

    @Test func importFlowSendsNoCoordinates() async throws {
        let api = api()
        // ImportSavedScreen: Takeout matching pulls a flat venue list, no geo.
        _ = try await api.fetchVenues(VenueQuery(limit: 200))

        let request = try #require(RecordingURLProtocol.requests.first)
        #expect(request.host == Self.engineHost)
        #expect(coordinateNames(in: request).isEmpty)
        #expect(Set(request.queryNames) == ["sort", "limit", "radius_m"])
    }

    // MARK: Location granted (inside coverage)

    @Test func grantedCoordinatesReachOnlyTheEngine() async throws {
        let api = api()
        // A device coordinate inside NYC coverage (Empire State Building).
        let device = (lat: 40.7484, lng: -73.9857)
        let granted = VenueQuery(lat: device.lat, lng: device.lng, radiusM: 2_500, sort: .workScore, limit: 100)
        try await runReadFlows(api, query: granted)
        let photos = try await api.fetchPhotos(venueId: "curated-devocin")

        let requests = RecordingURLProtocol.requests
        #expect(requests.count == 6)

        // 1. No request left the device for any host but the venue engine.
        #expect(Set(requests.compactMap(\.host)) == [Self.engineHost])

        // 2. The device coordinate appears in exactly one request: the venue
        //    query — and only as lat/lng.
        let digits = [String(device.lat), String(device.lng), "40.748", "73.985"]
        let carrying = requests.filter { request in digits.contains { request.contains($0) } }
        #expect(carrying.count == 1)
        #expect(carrying.first?.method == "GET")
        #expect(carrying.first?.path == "/v1/venues")
        #expect(carrying.first.map(coordinateNames) == ["lat", "lng"])

        // 3. Photo URLs point at a third-party (Google) host that is NOT the
        //    engine — and those URLs carry neither coordinates nor the device
        //    coordinate digits. (Bytes are fetched by AsyncImage out of band;
        //    the URL is the only thing the app can send it.)
        #expect(!photos.isEmpty)
        for photo in photos {
            let url = try #require(URL(string: photo.url))
            #expect(url.host != Self.engineHost)
            #expect(url.host == "lh3.googleusercontent.com")
            let names = Set((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map(\.name))
            #expect(names.intersection(Self.coordinateKeys).isEmpty)
            #expect(!digits.contains { photo.url.contains($0) })
            if let attribution = photo.attributionUri {
                #expect(!digits.contains { attribution.contains($0) })
            }
        }
    }

    // MARK: Write paths (not reachable in the v1 UI, pinned anyway)

    @Test func observationAndSpeedTestCarryNoLocation() async throws {
        let api = api()
        _ = try await api.submitSpeedTest(venueId: "curated-devocin", mbpsDown: 42)
        _ = try await api.measureDownloadMbps(samples: 1)

        let requests = RecordingURLProtocol.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.host == Self.engineHost })

        let observation = try #require(requests.first { $0.method == "POST" })
        #expect(observation.path == "/v1/observations")
        #expect(observation.bodyKeys == ["venueId", "kind", "mbpsDown"])
        #expect(coordinateNames(in: observation).isEmpty)

        let probe = try #require(requests.first { $0.method == "GET" })
        #expect(probe.path == "/v1/venues")
        #expect(Set(probe.queryNames) == ["limit", "_speed_test_nonce"])
    }

    // MARK: Wire vocabulary guard

    /// The complete set of query names `VenueQuery` can emit. Adding a name
    /// here is a privacy review: which ones can carry a location?
    @Test func queryVocabularyIsClosed() {
        let everything = VenueQuery(
            lat: 1, lng: 2, radiusM: 3,
            wifiMinimum: .fast, outletMinimum: .plenty, seatingMinimum: .some,
            venueType: .cafe, laptopFriendlyOnly: true,
            neighborhood: "Williamsburg", search: "oat", sort: .distance, limit: 9
        )
        let names = Set(everything.urlQueryItems.map(\.name))
        #expect(names == [
            "sort", "limit", "radius_m", "lat", "lng",
            "wifi_min", "outlets_min", "minSeating", "venueType", "laptops",
            "neighborhood", "q",
        ])
        #expect(names.intersection(Self.coordinateKeys) == ["lat", "lng"])
    }
}
