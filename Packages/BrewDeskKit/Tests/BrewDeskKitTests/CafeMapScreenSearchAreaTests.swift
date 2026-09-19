import MapKit
import Testing
@testable import BrewDeskKit

/// `CafeMapScreen.radiusMeters(for:)` and `.needsSearchAreaPill(...)`
/// (bd#192): the pure geometry/hysteresis behind the "Search this area"
/// pill, kept separate from the gesture/state wiring in `CafeMapScreen`
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

    // MARK: - needsSearchAreaPill

    @Test func sameCenterAndRadiusNeedsNoPill() {
        let loaded = region(latDelta: 0.018, lngDelta: 0.018) // radius ≈ VenuesModel.defaultRadiusM-ish
        let needs = CafeMapScreen.needsSearchAreaPill(
            loadedCenterLat: Self.unionSquare.latitude,
            loadedCenterLng: Self.unionSquare.longitude,
            loadedRadiusM: CafeMapScreen.radiusMeters(for: loaded),
            visibleRegion: loaded
        )
        #expect(!needs)
    }

    @Test func smallPanUnderThirtyFivePercentNeedsNoPill() {
        let loadedRadius = 1000
        // ~0.001° longitude at this latitude ≈ 84 m — under 35% of 1000 m.
        let nearby = region(
            center: CLLocationCoordinate2D(
                latitude: Self.unionSquare.latitude, longitude: Self.unionSquare.longitude + 0.001
            ),
            latDelta: 0.018, lngDelta: 0.018
        )
        let needs = CafeMapScreen.needsSearchAreaPill(
            loadedCenterLat: Self.unionSquare.latitude,
            loadedCenterLng: Self.unionSquare.longitude,
            loadedRadiusM: loadedRadius,
            visibleRegion: nearby
        )
        #expect(!needs)
    }

    @Test func panPastThirtyFivePercentNeedsThePill() {
        let loadedRadius = 1000
        // ~0.01° longitude at this latitude ≈ 843 m — past 35% of 1000 m.
        let farAway = region(
            center: CLLocationCoordinate2D(
                latitude: Self.unionSquare.latitude, longitude: Self.unionSquare.longitude + 0.01
            ),
            latDelta: 0.018, lngDelta: 0.018
        )
        let needs = CafeMapScreen.needsSearchAreaPill(
            loadedCenterLat: Self.unionSquare.latitude,
            loadedCenterLng: Self.unionSquare.longitude,
            loadedRadiusM: loadedRadius,
            visibleRegion: farAway
        )
        #expect(needs)
    }

    @Test func zoomOutPastTwiceTheRadiusNeedsThePill() {
        // Loaded at a 500 m radius; the visible region now implies ~1500 m.
        let loadedRadius = 500
        let zoomedOut = region(latDelta: 0.027, lngDelta: 0.027)
        let needs = CafeMapScreen.needsSearchAreaPill(
            loadedCenterLat: Self.unionSquare.latitude,
            loadedCenterLng: Self.unionSquare.longitude,
            loadedRadiusM: loadedRadius,
            visibleRegion: zoomedOut
        )
        #expect(needs)
    }

    @Test func zoomInPastHalfTheRadiusNeedsThePill() {
        // Loaded at a 2000 m radius; the visible region now implies ~500 m.
        let loadedRadius = 2000
        let zoomedIn = region(latDelta: 0.009, lngDelta: 0.009)
        let needs = CafeMapScreen.needsSearchAreaPill(
            loadedCenterLat: Self.unionSquare.latitude,
            loadedCenterLng: Self.unionSquare.longitude,
            loadedRadiusM: loadedRadius,
            visibleRegion: zoomedIn
        )
        #expect(needs)
    }
}
