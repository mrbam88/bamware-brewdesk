import Foundation
import Testing
@testable import BrewDeskKit
import VenueKit

@Suite @MainActor struct SavedVenuesStoreTests {
    @Test func togglesAndPersistsMostRecentFirst() {
        let persistence = MemorySavedPersistence()
        let store = SavedVenuesStore(persistence: persistence)

        store.toggle("first")
        store.toggle("second")
        #expect(store.venueIDs == ["second", "first"])
        #expect(persistence.saved == ["second", "first"])

        store.toggle("second")
        #expect(store.venueIDs == ["first"])
        #expect(!store.contains("second"))
    }

    @Test func savedModelHydratesInPersistedOrder() async {
        let first = venue(id: "first", name: "First Cafe")
        let second = venue(id: "second", name: "Second Cafe")
        let model = SavedVenuesModel(service: StubVenueDetails(venues: [first, second]))

        await model.load(venueIDs: ["second", "first"])

        #expect(model.phase == .loaded)
        #expect(model.venues.map(\.id) == ["second", "first"])
    }

    private func venue(id: String, name: String) -> Venue {
        let claim = Claim(value: "unknown", source: "estimate", confidence: 0.3, observedAt: "2026-08-01")
        return Venue(
            id: id,
            name: name,
            lat: 40.73,
            lng: -73.99,
            address: nil,
            neighborhood: "NoHo",
            borough: "Manhattan",
            hoursRaw: nil,
            vertical: "cafe",
            attributes: VenueAttributes(wifi: claim, outlets: claim, laptopPolicy: claim, noise: claim),
            vibeTags: [],
            workScore: 60,
            lastVerified: nil,
            distanceM: nil
        )
    }
}

@MainActor
private final class MemorySavedPersistence: SavedVenuePersisting {
    var saved: [String] = []

    func loadVenueIDs() -> [String] { saved }
    func saveVenueIDs(_ venueIDs: [String]) { saved = venueIDs }
}

private struct StubVenueDetails: VenueDetailServing {
    let venues: [Venue]

    func fetchVenue(id: String) async throws -> Venue {
        guard let venue = venues.first(where: { $0.id == id }) else {
            throw StubError.missing
        }
        return venue
    }

    private enum StubError: Error { case missing }
}
