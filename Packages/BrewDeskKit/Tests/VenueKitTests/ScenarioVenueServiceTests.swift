import Foundation
import Testing
@testable import VenueKit

/// Each scenario's contract — the UI tests lean on these being exact.
@Suite struct ScenarioVenueServiceTests {
    private let query = VenueQuery(limit: 50)

    @Test func fixtureOKServesVenuesHealthAndUnloadablePhotos() async throws {
        let service = ScenarioVenueService(scenario: .fixtureOK)

        let venues = try await service.fetchVenues(query)
        #expect(venues.map(\.id) == ["fixture-roasters", "fixture-library", "fixture-corner"])
        #expect(try await service.fetchHealth()?.venueCount == 3)
        #expect(try await service.fetchVenue(id: "fixture-library").name == "Fixture Reading Room")

        let photos = try await service.fetchPhotos(venueId: "fixture-roasters")
        #expect(photos.count == 1)
        #expect(photos[0].url.hasPrefix("http://127.0.0.1:9/"))
        #expect(photos[0].attribution != nil)
    }

    /// brewdesk#49 contract: index 0 is the untouched Google-attributed
    /// fixture photo, index 1 the community photo whose byline the UI pins.
    @Test func communityPhotosServesGoogleAndCommunityFixtures() async throws {
        let service = ScenarioVenueService(scenario: .communityPhotos)

        // Venue + health paths behave like fixtureOK.
        let venues = try await service.fetchVenues(query)
        #expect(venues.map(\.id) == ["fixture-roasters", "fixture-library", "fixture-corner"])
        #expect(try await service.fetchHealth()?.ok == true)
        #expect(try await service.fetchVenue(id: "fixture-roasters").name == "Fixture Roasters")

        let photos = try await service.fetchPhotos(venueId: "fixture-roasters")
        #expect(photos.count == 2)

        let google = photos[0]
        #expect(google.attribution == "Fixture Photographer")
        #expect(google.attributionUri != nil)
        #expect(google.communityByline == nil)

        let community = photos[1]
        #expect(community.communityByline == "Ada L.")
        #expect(community.attribution == nil)
        #expect(community.attributionUri == nil)
        #expect(community.url.hasPrefix("http://127.0.0.1:9/"))
    }

    @Test func fixturesCarryHumanProvenanceAndRoundTrip() throws {
        for venue in ScenarioVenueService.fixtureVenues {
            #expect(venue.attributes.wifi.source == "curated")
            #expect(venue.attributes.wifi.observedAt.count >= 10)
            let data = try JSONEncoder().encode(venue)
            #expect(try JSONDecoder().decode(Venue.self, from: data) == venue)
        }
    }

    @Test func engineDownThrowsHTTP500Everywhere() async {
        let service = ScenarioVenueService(scenario: .engineDown)
        await #expect(throws: VenueAPIError.http(statusCode: 500)) { try await service.fetchVenues(query) }
        await #expect(throws: VenueAPIError.http(statusCode: 500)) { try await service.fetchHealth() }
        await #expect(throws: VenueAPIError.http(statusCode: 500)) { try await service.fetchVenue(id: "fixture-roasters") }
        await #expect(throws: VenueAPIError.http(statusCode: 500)) { try await service.fetchPhotos(venueId: "fixture-roasters") }
    }

    @Test func offlineThrowsURLErrorEverywhere() async {
        let service = ScenarioVenueService(scenario: .offline)
        await #expect(throws: URLError(.notConnectedToInternet)) { try await service.fetchVenues(query) }
        await #expect(throws: URLError(.notConnectedToInternet)) { try await service.fetchPhotos(venueId: "x") }
    }

    @Test func offlineThenRecoversFailsExactlyOnce() async throws {
        let service = ScenarioVenueService(scenario: .offlineThenRecovers)
        await #expect(throws: URLError(.notConnectedToInternet)) { try await service.fetchVenues(query) }
        #expect(try await service.fetchVenues(query).count == 3)
        #expect(try await service.fetchVenues(query).count == 3)
        #expect(try await service.fetchHealth()?.ok == true)
        // A fresh instance starts over — the counter is per service, not global.
        await #expect(throws: URLError(.notConnectedToInternet)) {
            try await ScenarioVenueService(scenario: .offlineThenRecovers).fetchVenues(query)
        }
    }

    @Test func emptyVenuesIsASuccessfulEmptyAnswer() async throws {
        let service = ScenarioVenueService(scenario: .emptyVenues)
        #expect(try await service.fetchVenues(query).isEmpty)
        #expect(try await service.fetchHealth()?.ok == true)
    }

    @Test func photoScenariosLeaveVenuesHealthy() async throws {
        let empty = ScenarioVenueService(scenario: .photosEmpty)
        #expect(try await empty.fetchVenues(query).count == 3)
        #expect(try await empty.fetchPhotos(venueId: "fixture-roasters").isEmpty)

        let failing = ScenarioVenueService(scenario: .photosFail)
        #expect(try await failing.fetchVenues(query).count == 3)
        await #expect(throws: VenueAPIError.http(statusCode: 500)) {
            try await failing.fetchPhotos(venueId: "fixture-roasters")
        }
    }

    @Test func unknownVenueIs404InHealthyScenarios() async {
        let service = ScenarioVenueService(scenario: .fixtureOK)
        await #expect(throws: VenueAPIError.http(statusCode: 404)) {
            try await service.fetchVenue(id: "missing-cafe")
        }
    }

    @Test func slowHonoursCancellation() async {
        let service = ScenarioVenueService(scenario: .slow)
        let task = Task { try await service.fetchVenues(VenueQuery(limit: 1)) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func defaultSessionFailsFast() {
        #expect(VenueAPI.defaultSession.configuration.timeoutIntervalForRequest == 15)
        #expect(VenueAPI.defaultSession.configuration.waitsForConnectivity == false)
    }
}
