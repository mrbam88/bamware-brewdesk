import Foundation
import MapKit
import Testing
import VenueKit
@testable import BrewDeskKit

/// `CafeMapScreen.searchFitRegion` — the pure camera-fit geometry behind
/// brewdesk#158 ("search moves the map to the results"). Kept separate from
/// the gesture/debounce wiring in `CafeMapScreen` itself (untestable outside
/// a running `Map`), so this exercises only the deterministic math: one
/// result centers at neighborhood zoom, several fit their bounding box, and
/// the fit leaves room for the shelf card.
struct CafeMapScreenSearchFitTests {

    private func venue(id: String, lat: Double, lng: Double) -> Venue {
        let observedAt = "2026-08-01T00:00:00Z"
        return Venue(
            id: id,
            name: "Venue \(id)",
            lat: lat,
            lng: lng,
            address: nil,
            neighborhood: "Test",
            borough: "Manhattan",
            hoursRaw: nil,
            vertical: "cafe",
            attributes: VenueAttributes(
                wifi: Claim(value: "fast", mbpsRange: nil, source: "curated", confidence: 0.9, observedAt: observedAt),
                outlets: Claim(value: "some", source: "curated", confidence: 0.9, observedAt: observedAt),
                laptopPolicy: Claim(value: "unrestricted", source: "curated", confidence: 0.9, observedAt: observedAt),
                noise: Claim(value: "moderate", source: "agent", confidence: 0.6, observedAt: observedAt),
                seating: Claim(value: "some", source: "agent", confidence: 0.6, observedAt: observedAt)
            ),
            vibeTags: [],
            workScore: 50,
            lastVerified: nil,
            distanceM: nil
        )
    }

    @Test func emptyResultsFitNothing() {
        #expect(CafeMapScreen.searchFitRegion(for: [], mapHeight: 800, shelfClearance: 260) == nil)
    }

    @Test func singleResultCentersAtNeighborhoodZoom() throws {
        let target = venue(id: "a", lat: 40.7359, lng: -73.9911)
        // No shelf/height info supplied ⇒ no vertical bias, so the fit is
        // exactly the neighborhood-zoom span centered on the venue.
        let region = CafeMapScreen.searchFitRegion(for: [target], mapHeight: 0, shelfClearance: 0)
        let unwrapped = try #require(region)
        #expect(unwrapped.center.latitude == target.lat)
        #expect(unwrapped.center.longitude == target.lng)
        #expect(unwrapped.span.latitudeDelta == 0.012)
        #expect(unwrapped.span.longitudeDelta == 0.012)
    }

    @Test func multipleResultsFitThePaddedBoundingBox() throws {
        let venues = [
            venue(id: "a", lat: 40.730, lng: -73.995),
            venue(id: "b", lat: 40.742, lng: -73.987)
        ]
        let region = CafeMapScreen.searchFitRegion(for: venues, mapHeight: 0, shelfClearance: 0)
        let unwrapped = try #require(region)

        // Center is the bounding-box midpoint (no shelf bias supplied).
        #expect(abs(unwrapped.center.latitude - 40.736) < 0.0001)
        #expect(abs(unwrapped.center.longitude - (-73.991)) < 0.0001)

        // Span comfortably exceeds the raw box (padding), and both results
        // fall well inside it.
        let rawLatSpan = 40.742 - 40.730
        let rawLngSpan = -73.987 - (-73.995)
        #expect(unwrapped.span.latitudeDelta > rawLatSpan)
        #expect(unwrapped.span.longitudeDelta > rawLngSpan)
        for v in venues {
            #expect(abs(v.lat - unwrapped.center.latitude) <= unwrapped.span.latitudeDelta / 2)
            #expect(abs(v.lng - unwrapped.center.longitude) <= unwrapped.span.longitudeDelta / 2)
        }
    }

    @Test func shelfClearanceShiftsTheFitNorthOfTheRawCenter() throws {
        let target = venue(id: "a", lat: 40.7359, lng: -73.9911)
        // A tall shelf relative to the map height reserves real room at the
        // bottom, so the fitted region's center must sit south of the
        // venue's true latitude — pushing the venue itself further north
        // on screen, clear of the card.
        let region = CafeMapScreen.searchFitRegion(for: [target], mapHeight: 800, shelfClearance: 300)
        let unwrapped = try #require(region)
        #expect(unwrapped.center.latitude < target.lat)
        // The venue must still fall within the fitted span.
        #expect(abs(target.lat - unwrapped.center.latitude) <= unwrapped.span.latitudeDelta / 2)
    }

    @Test func degenerateHeightFallsBackToNoBias() throws {
        let target = venue(id: "a", lat: 40.7359, lng: -73.9911)
        // Shelf clearance at or beyond the reported map height must not
        // divide by zero or invert the fit — falls back to no vertical bias.
        let region = CafeMapScreen.searchFitRegion(for: [target], mapHeight: 200, shelfClearance: 260)
        let unwrapped = try #require(region)
        #expect(unwrapped.center.latitude == target.lat)
    }
}
