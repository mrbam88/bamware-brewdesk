import MapKit
import Testing
@testable import BrewDeskKit

/// `CafeMapScreen.radiusMeters(for:)` (bd#192) and `.viewport(for:mapWidth:)`
/// (bd#267): the pure geometry behind viewport fetches — the "Search this
/// area" pill and auto-load on pan — kept separate from the gesture/state
/// wiring in `CafeMapScreen`
/// itself (untestable outside a running `Map`) — same split
/// `CafeMapScreenSearchFitTests` already uses for brewdesk#158.
struct CafeMapScreenSearchAreaTests {
    private static let unionSquare = CLLocationCoordinate2D(latitude: 40.7359, longitude: -73.9911)

    private func region(
        center: CLLocationCoordinate2D = unionSquare, latDelta: Double, lngDelta: Double
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
        )
    }

    // MARK: - radiusMeters(for:)

    @Test func radiusIsHalfTheLongerVisibleSide() {
        // ~0.018° latitude ≈ 2004 m tall (the longer side; longitude here
        // is deliberately much narrower) — half ≈ 1002 m, well inside the
        // clamp, so the result should track the geometry closely.
        let tall = region(latDelta: 0.018, lngDelta: 0.002)
        let radius = CafeMapScreen.radiusMeters(for: tall)
        #expect(radius > 900 && radius < 1100)
    }

    @Test func radiusClampsToTheMinimum() {
        let tiny = region(latDelta: 0.0005, lngDelta: 0.0005)
        #expect(CafeMapScreen.radiusMeters(for: tiny) == VenuesModel.minRadiusM)
    }

    @Test func radiusClampsToTheMaximum() {
        let huge = region(latDelta: 0.5, lngDelta: 0.5)
        #expect(CafeMapScreen.radiusMeters(for: huge) == VenuesModel.maxRadiusM)
    }

    // MARK: - viewport(for:mapWidth:) (bd#267)

    @Test func viewportCarriesCentreRadiusShorterSideAndZoom() throws {
        // A portrait phone window: ~1,100 m wide, ~1,670 m tall, 393 pt wide.
        let portrait = region(latDelta: 0.015, lngDelta: 0.01304)
        let viewport = try #require(CafeMapScreen.viewport(for: portrait, mapWidth: 393))
        #expect(viewport.centerLat == Self.unionSquare.latitude)
        #expect(viewport.centerLng == Self.unionSquare.longitude)
        // Radius: half the LONGER side. Span: the SHORTER side.
        #expect(viewport.radiusM == CafeMapScreen.radiusMeters(for: portrait))
        #expect(viewport.radiusM > 800 && viewport.radiusM < 870)
        #expect(viewport.spanM > 1_050 && viewport.spanM < 1_150)
        #expect(viewport.metersPerPoint > 2.6 && viewport.metersPerPoint < 3.0)
    }

    @Test func cityWideViewportReportsAZoomPastTheAutoLoadLimit() throws {
        // ~17.7 km across a 393 pt map ≈ 45 m/pt.
        let cityWide = region(latDelta: 0.32, lngDelta: 0.21)
        let viewport = try #require(CafeMapScreen.viewport(for: cityWide, mapWidth: 393))
        #expect(viewport.metersPerPoint > VenuesModel.autoLoadMaxMetersPerPoint)
        #expect(viewport.radiusM == VenuesModel.maxRadiusM)
    }

    @Test func noViewportBeforeTheMapHasASize() {
        #expect(CafeMapScreen.viewport(for: region(latDelta: 0.015, lngDelta: 0.013), mapWidth: 0) == nil)
    }
}
