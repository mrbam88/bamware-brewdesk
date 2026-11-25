import Foundation
import MapKit
import Testing
import VenueKit
@testable import BrewDeskKit

/// brewdesk#211 — `CafeMapCanvas` rebuilds the `Map` only when its
/// `CafeMapCanvasContent` differs. These pin down what "differs" means: the
/// same drawing must compare equal (so the rebuild is skipped), and anything
/// that changes a marker must not.
@Suite @MainActor struct CafeMapCanvasTests {
    private static let mapSize = CGSize(width: 393, height: 660)
    private static let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: VenuesModel.coverageCenterLat, longitude: VenuesModel.coverageCenterLng),
        span: MKCoordinateSpan(latitudeDelta: 0.0155, longitudeDelta: 0.0155)
    )

    private func venues() async throws -> [Venue] {
        try await ScenarioVenueService(scenario: .manyVenues).fetchVenues(VenueQuery(
            lat: VenuesModel.coverageCenterLat, lng: VenuesModel.coverageCenterLng,
            radiusM: VenuesModel.defaultRadiusM
        ))
    }

    private func plan(_ venues: [Venue], selected: String? = nil) -> MapAnnotationPlan {
        MapAnnotationPlanner.plan(
            venues: venues, region: Self.region, mapSize: Self.mapSize, selectedVenueID: selected
        )
    }

    private func content(
        _ plan: MapAnnotationPlan, selected: Venue? = nil, metersPerPoint: Double = 3.3,
        gapFill: [AppleUnverifiedPOI] = []
    ) -> CafeMapCanvasContent {
        CafeMapCanvasContent(plan: plan, selected: selected, metersPerPoint: metersPerPoint, gapFillMarkers: gapFill)
    }

    @Test func theSameDrawingComparesEqualEvenWhenPlannedTwice() async throws {
        let venues = try await venues()
        let first = plan(venues)
        let second = plan(venues)
        #expect(first.annotationCount > 0)
        #expect(content(first) == content(first))
        #expect(content(first) == content(second))
    }

    @Test func aDifferentPlanDoesNotCompareEqual() async throws {
        let venues = try await venues()
        let all = plan(venues)
        let fewer = plan(Array(venues.dropFirst(venues.count / 2)))
        #expect(all != fewer)
        #expect(content(all) != content(fewer))
    }

    @Test func selectingAPlacedVenueChangesThePlanNotTheFallbackPin() async throws {
        let venues = try await venues()
        let unselected = plan(venues)
        let pick = try #require(unselected.teardrops.first?.venue)
        let selectedPlan = plan(venues, selected: pick.id)

        let selected = content(selectedPlan, selected: pick)
        #expect(selected.unplacedSelection == nil)
        #expect(selected != content(unselected))
    }

    @Test func aSelectionThePlanDidNotPlaceGetsTheFallbackPin() async throws {
        let venues = try await venues()
        let placed = plan(venues)
        let outsider = try #require(venues.first { !placed.containsVenue(id: $0.id) })

        let withOutsider = content(placed, selected: outsider)
        #expect(withOutsider.unplacedSelection == outsider)
        #expect(withOutsider != content(placed))
    }

    @Test func dotSizesFollowTheZoomExactlyAsBefore() async throws {
        let placed = plan(try await venues())
        let near = content(placed, metersPerPoint: 3.3)
        #expect(near.dotRadius == 2.0 * 3.3)
        #expect(near.unratedDotRadius == 1.5 * 3.3)
        #expect(near.unratedDotOpacity == MapAnnotationPlanner.unratedDotOpacity(forMetersPerPoint: 3.3))

        let far = content(placed, metersPerPoint: 14)
        #expect(far.dotRadius == 15)
        #expect(far.unratedDotRadius == 21)
        #expect(far != near)
        // The closest zoom clamps to the floor.
        #expect(content(placed, metersPerPoint: 0.5).dotRadius == 3)
        #expect(content(placed, metersPerPoint: 0.5).unratedDotRadius == 2)
    }

    @Test func gapFillMarkersArePartOfTheDrawing() async throws {
        let placed = plan(try await venues())
        let poi = AppleUnverifiedPOI(
            name: "Somewhere", coordinate: CLLocationCoordinate2D(latitude: 40.73, longitude: -73.99)
        )
        #expect(content(placed, gapFill: [poi]) != content(placed))
        #expect(content(placed, gapFill: [poi]) == content(placed, gapFill: [poi]))
    }
}
