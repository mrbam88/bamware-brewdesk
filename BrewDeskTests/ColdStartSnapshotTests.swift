import Foundation
import Testing
import VenueKit
@testable import BrewDesk

/// The bundled first-paint snapshot (brewdesk#28) must actually ship in the
/// Release bundle and describe the coverage area — otherwise cold start
/// silently degrades to the spinner this ticket removed.
@Suite @MainActor struct ColdStartSnapshotTests {
    @Test func snapshotShipsInTheBundleWithCoverageVenues() throws {
        #expect(Bundle.main.url(forResource: VenueSnapshot.resourceName, withExtension: "json") != nil)
        let venues = VenueSnapshot.load()
        #expect(venues.count >= 40, "snapshot too small to be a useful first paint: \(venues.count)")
        #expect(Set(venues.map(\.id)).count == venues.count, "duplicate venue ids")
        for venue in venues {
            // ~5 km box around the Union Square anchor (40.7359, -73.9911).
            #expect(abs(venue.lat - 40.7359) < 0.045 && abs(venue.lng + 73.9911) < 0.06,
                    "\(venue.name) is outside the Union Square query radius")
            #expect(venue.distanceM == nil, "\(venue.name) carries a stale distance")
        }
    }

    @Test func snapshotIsSmallEnoughNotToBloatTheBinary() throws {
        let url = try #require(Bundle.main.url(forResource: VenueSnapshot.resourceName, withExtension: "json"))
        let bytes = try Data(contentsOf: url).count
        #expect(bytes < 100_000, "snapshot is \(bytes) bytes — trim it before shipping")
    }
}
