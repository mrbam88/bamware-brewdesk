import Foundation
import MapKit
import Testing
import VenueKit
@testable import BrewDeskKit

/// Representation planning for the map (brewdesk#54): viewport culling,
/// density thresholds, and stable grid clustering.
struct MapAnnotationPlannerTests {

    // MARK: - Helpers

    private func venue(id: String, lat: Double, lng: Double, score: Int = 50) -> Venue {
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
            workScore: score,
            lastVerified: nil,
            distanceM: nil
        )
    }

    /// `count` venues spread evenly inside the given box.
    private func grid(count: Int, centerLat: Double = 40.7359, centerLng: Double = -73.9911, extent: Double = 0.02) -> [Venue] {
        let columns = Int(Double(count).squareRoot().rounded(.up))
        return (0..<count).map { index in
            venue(
                id: "g\(index)",
                lat: centerLat - extent / 2 + Double(index / columns) / Double(columns) * extent,
                lng: centerLng - extent / 2 + Double(index % columns) / Double(columns) * extent,
                score: (index * 37) % 101
            )
        }
    }

    private func region(lat: Double = 40.7359, lng: Double = -73.9911, span: Double = 0.035) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
    }

    // MARK: - Culling

    @Test func cullingKeepsVenuesInsideRegionAndMargin() {
        let inside = venue(id: "inside", lat: 40.7359, lng: -73.9911)
        // 0.035 span + 50% margin ⇒ padded half-height 0.035·(0.5+0.5) = 0.035°.
        let inMargin = venue(id: "margin", lat: 40.7359 + 0.030, lng: -73.9911)
        let outside = venue(id: "outside", lat: 40.7359 + 0.05, lng: -73.9911)
        let farOutside = venue(id: "far", lat: 40.9, lng: -73.7)

        let culled = MapAnnotationPlanner.culled([inside, inMargin, outside, farOutside], region: region())
        #expect(culled.map(\.id) == ["inside", "margin"])
    }

    @Test func cullingPreservesModelOrder() {
        let venues = grid(count: 30)
        let culled = MapAnnotationPlanner.culled(venues, region: region())
        #expect(culled.map(\.id) == venues.map(\.id))
    }

    // MARK: - Representation thresholds

    @Test func fewVisibleVenuesGetFullPins() {
        let plan = MapAnnotationPlanner.plan(venues: grid(count: MapAnnotationPlanner.pinLimit), region: region())
        guard case .pins(let venues) = plan else {
            Issue.record("expected pins, got \(plan)")
            return
        }
        #expect(venues.count == MapAnnotationPlanner.pinLimit)
    }

    @Test func midDensityGetsDots() {
        let plan = MapAnnotationPlanner.plan(venues: grid(count: 100), region: region())
        guard case .dots(let venues) = plan else {
            Issue.record("expected dots, got \(plan)")
            return
        }
        #expect(venues.count == MapAnnotationPlanner.dotBudget)
    }

    @Test func dotBudgetKeepsTheBestRankedVisibleVenues() {
        // The model orders venues by Work Fit; culling preserves that order,
        // so the budget keeps exactly the top of the ranking.
        let venues = grid(count: 100)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: region())
        guard case .dots(let dots) = plan else {
            Issue.record("expected dots, got \(plan)")
            return
        }
        #expect(dots.map(\.id) == venues.prefix(MapAnnotationPlanner.dotBudget).map(\.id))
    }

    @Test func highDensityGetsClusters() {
        let plan = MapAnnotationPlanner.plan(venues: grid(count: 600), region: region())
        guard case .clusters(let clusters) = plan else {
            Issue.record("expected clusters, got \(plan)")
            return
        }
        #expect(clusters.count > 1)
        #expect(clusters.count < 600 / 2, "clustering should collapse most venues")
    }

    @Test func fullDatasetScaleCollapsesToDozensOfAnnotations() {
        // The #54 pathology: dataset-size venue counts must never become
        // per-venue annotations.
        let plan = MapAnnotationPlanner.plan(venues: grid(count: 2_180, extent: 0.12), region: region())
        #expect(plan.annotationCount <= 80)
    }

    @Test func offscreenVenuesNeverForceClustering() {
        // 600 venues far away + 3 nearby: the viewport only sees 3 ⇒ pins.
        let far = grid(count: 600, centerLat: 40.9, centerLng: -73.7, extent: 0.02)
        let near = grid(count: 3)
        let plan = MapAnnotationPlanner.plan(venues: far + near, region: region())
        guard case .pins(let venues) = plan else {
            Issue.record("expected pins, got \(plan)")
            return
        }
        #expect(venues.count == 3)
    }

    // MARK: - Clusters

    @Test func clusterCountsSumToVisibleVenues() {
        let venues = grid(count: 400)
        let clusters = MapAnnotationPlanner.clusters(for: venues, spanLongitude: 0.035)
        #expect(clusters.map(\.count).reduce(0, +) == 400)
    }

    @Test func clusterCentroidLiesWithinItsVenues() {
        let venues = grid(count: 400)
        let clusters = MapAnnotationPlanner.clusters(for: venues, spanLongitude: 0.035)
        let minLat = venues.map(\.lat).min()!
        let maxLat = venues.map(\.lat).max()!
        for cluster in clusters {
            #expect(cluster.latitude >= minLat && cluster.latitude <= maxLat)
        }
    }

    @Test func clusterBestScoreIsCellMaximum() {
        let low = venue(id: "low", lat: 40.7359, lng: -73.9911, score: 10)
        let high = venue(id: "high", lat: 40.7360, lng: -73.9912, score: 93)
        let clusters = MapAnnotationPlanner.clusters(for: [low, high], spanLongitude: 0.5)
        #expect(clusters.count == 1)
        #expect(clusters.first?.bestScore == 93)
    }

    @Test func clusterPlansAreIdenticalAcrossPansAtSameZoom() {
        // The zero-churn guarantee behind buttery pans at dataset scale: the
        // cluster grid is absolute, so a pan (same zoom) re-plans to the very
        // same annotations and SwiftUI diffs away the whole update.
        let venues = grid(count: 2_180, extent: 0.12)
        let before = MapAnnotationPlanner.plan(venues: venues, region: region())
        let panned = MapAnnotationPlanner.plan(
            venues: venues,
            region: region(lat: 40.7359 + 0.02, lng: -73.9911 - 0.015)
        )
        #expect(before == panned)
        guard case .clusters = before else {
            Issue.record("expected clusters at dataset scale, got \(before)")
            return
        }
    }

    @Test func clusterIdsAreStableAcrossPansAtSameZoom() {
        let venues = grid(count: 400)
        let before = MapAnnotationPlanner.clusters(for: venues, spanLongitude: 0.035)
        // Same venues, same zoom — a pan changes the region, not the grid.
        let after = MapAnnotationPlanner.clusters(for: venues, spanLongitude: 0.035)
        #expect(before == after)
    }

    @Test func cellSizeIsQuantizedAndMonotonic() {
        let fine = MapAnnotationPlanner.clusterCellDegrees(spanLongitude: 0.02)
        let coarse = MapAnnotationPlanner.clusterCellDegrees(spanLongitude: 0.32)
        #expect(fine < coarse)
        // Power-of-two quantization: pans and small span jitter at the same
        // zoom land on the same cell size, so clusters never re-bucket.
        for span in [0.02, 0.035, 0.1, 0.32] {
            let exponent = log2(MapAnnotationPlanner.clusterCellDegrees(spanLongitude: span))
            #expect(exponent == exponent.rounded(), "cell size must be a power of two (span \(span))")
        }
    }

    // MARK: - Re-plan hysteresis (CafeMapScreen)

    @Test func smallPansInsideTheMarginSkipReplanning() {
        let current = region()
        let nudged = region(lat: 40.7359 + 0.035 * 0.1, lng: -73.9911)
        #expect(!CafeMapScreen.needsReplan(from: current, to: nudged))
        #expect(CafeMapScreen.needsReplan(from: nil, to: current), "first camera always plans")
    }

    @Test func bigPansAndZoomsForceReplanning() {
        let current = region()
        let farPan = region(lat: 40.7359 + 0.035 * 0.5, lng: -73.9911)
        #expect(CafeMapScreen.needsReplan(from: current, to: farPan))
        let zoomIn = region(span: 0.035 / 3)
        #expect(CafeMapScreen.needsReplan(from: current, to: zoomIn))
        let zoomOut = region(span: 0.035 * 3)
        #expect(CafeMapScreen.needsReplan(from: current, to: zoomOut))
    }

    // MARK: - Plan helpers

    @Test func planKnowsWhichVenuesItRendersIndividually() {
        let venues = grid(count: 10)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: region())
        #expect(plan.containsVenue(id: venues[0].id))
        #expect(!plan.containsVenue(id: "absent"))

        let clustered = MapAnnotationPlanner.plan(venues: grid(count: 600), region: region())
        #expect(!clustered.containsVenue(id: "g0"), "clusters render no individual venue")
    }
}
