import Foundation
import MapKit
import Testing
import VenueKit
@testable import BrewDeskKit

/// Representation planning for the map (brewdesk#54, re-shaped bd#204):
/// viewport culling, always-visible score pins, dot budget, and stable grid
/// clustering with a density guard.
struct MapAnnotationPlannerTests {

    // MARK: - Helpers

    /// `observed: false` produces a venue with no scored claims at all
    /// (`isObserved == false`) — bd#159's "not checked yet" case, and
    /// bd#204's "never eligible for a top-pin slot" case.
    private func venue(id: String, lat: Double, lng: Double, score: Int = 50, observed: Bool = true) -> Venue {
        let observedAt = "2026-08-01T00:00:00Z"
        // `observed: false` gives every claim an `estimate` source at
        // sub-threshold confidence — `Venue.isObserved`'s exact "no real
        // evidence" definition (same pattern as `SavedVenuesStoreTests`).
        let unobservedClaim = Claim(value: "unknown", source: "estimate", confidence: 0.3, observedAt: observedAt)
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
            attributes: observed
                ? VenueAttributes(
                    wifi: Claim(value: "fast", mbpsRange: nil, source: "curated", confidence: 0.9, observedAt: observedAt),
                    outlets: Claim(value: "some", source: "curated", confidence: 0.9, observedAt: observedAt),
                    laptopPolicy: Claim(value: "unrestricted", source: "curated", confidence: 0.9, observedAt: observedAt),
                    noise: Claim(value: "moderate", source: "agent", confidence: 0.6, observedAt: observedAt),
                    seating: Claim(value: "some", source: "agent", confidence: 0.6, observedAt: observedAt)
                )
                : VenueAttributes(
                    wifi: unobservedClaim,
                    outlets: unobservedClaim,
                    laptopPolicy: unobservedClaim,
                    noise: unobservedClaim,
                    seating: unobservedClaim
                ),
            vibeTags: [],
            workScore: score,
            lastVerified: nil,
            distanceM: nil
        )
    }

    /// `count` venues spread evenly inside the given box.
    private func grid(
        count: Int,
        centerLat: Double = 40.7359,
        centerLng: Double = -73.9911,
        extent: Double = 0.02,
        observed: Bool = true
    ) -> [Venue] {
        let columns = Int(Double(count).squareRoot().rounded(.up))
        return (0..<count).map { index in
            venue(
                id: "g\(index)",
                lat: centerLat - extent / 2 + Double(index / columns) / Double(columns) * extent,
                lng: centerLng - extent / 2 + Double(index % columns) / Double(columns) * extent,
                score: (index * 37) % 101,
                observed: observed
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
        #expect(plan.pins.count == MapAnnotationPlanner.pinLimit)
        #expect(plan.dots.isEmpty)
        #expect(plan.clusters.isEmpty)
    }

    @Test func midDensityFillsPinsThenDots() {
        let extraDots = MapAnnotationPlanner.dotBudget - 5
        let venues = grid(count: MapAnnotationPlanner.pinLimit + extraDots)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: region())
        #expect(plan.pins.count == MapAnnotationPlanner.pinLimit)
        #expect(plan.dots.count == extraDots)
        #expect(plan.clusters.isEmpty)
    }

    @Test func dotBudgetIsRespectedAndOverflowClusters() {
        let venues = grid(count: MapAnnotationPlanner.pinLimit + MapAnnotationPlanner.dotBudget + 200)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: region())
        #expect(plan.pins.count == MapAnnotationPlanner.pinLimit)
        #expect(plan.dots.count == MapAnnotationPlanner.dotBudget)
        #expect(!plan.clusters.isEmpty, "overflow past the dot budget must cluster")
        #expect(plan.clusters.reduce(0) { $0 + $1.count } == 200)
    }

    // MARK: - bd#204: always-visible score pins

    @Test func top25ScorePinsAlwaysPresentWith300VenuesInView() {
        let venues = grid(count: 300)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: region())
        #expect(plan.pins.count == MapAnnotationPlanner.pinLimit)

        let expectedTop = Set(
            venues.sorted { $0.workScore != $1.workScore ? $0.workScore > $1.workScore : $0.id < $1.id }
                .prefix(MapAnnotationPlanner.pinLimit)
                .map(\.id)
        )
        #expect(Set(plan.pins.map(\.id)) == expectedTop, "pins must be the top-ranked venues, not an arbitrary prefix")

        // No pinned venue is also counted in a dot or a cluster.
        let pinIDs = Set(plan.pins.map(\.id))
        #expect(plan.dots.allSatisfy { !pinIDs.contains($0.id) })
    }

    @Test func unobservedVenuesNeverTakeAPinSlot() {
        // 300 unobserved venues plus 5 observed ones with real scores: the
        // 5 observed venues must be the pins, never a fabricated-score
        // unobserved venue (bd#159's rule extended to bd#204's pin promotion).
        let unobserved = grid(count: 300, observed: false)
        let observed = (0..<5).map { venue(id: "obs\($0)", lat: 40.7359, lng: -73.9911, score: 90, observed: true) }
        let plan = MapAnnotationPlanner.plan(venues: unobserved + observed, region: region())
        #expect(plan.pins.count == 5)
        #expect(Set(plan.pins.map(\.id)) == Set(observed.map(\.id)))
    }

    // MARK: - bd#204: cluster density guard

    @Test func noClusterExceedsMaxShareOfVisibleVenues() {
        // A realistic dense viewport (the West Village screenshot shape:
        // 500 venues spread over a few blocks) — the guard must hold end to
        // end through `plan()`, not just in the unit-tested subdivide step.
        let venues = grid(count: 500)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: region())
        let visibleCount = venues.count
        for cluster in plan.clusters {
            #expect(
                Double(cluster.count) <= Double(visibleCount) * MapAnnotationPlanner.maxClusterShare + 0.001,
                "cluster \(cluster.id) holds \(cluster.count)/\(visibleCount) venues — exceeds the \(MapAnnotationPlanner.maxClusterShare) share guard"
            )
        }
    }

    @Test func subdivideOversizedSplitsACellThatExceedsTheShareGuard() {
        // Two groups placed at opposite ends of ONE coarse cell (same
        // longitude bucket, latitudes in the cell's first vs. second half)
        // so halving the cell for subdivision lands them in different finer
        // buckets — the guard should split them into (at least) two clusters
        // once the combined cell is over the 40% line.
        let spanLongitude = 0.035
        let cell = MapAnnotationPlanner.clusterCellDegrees(spanLongitude: spanLongitude)
        let lngFixed = 0.5 * cell
        let groupA = (0..<60).map { venue(id: "a\($0)", lat: 0.1 * cell, lng: lngFixed, score: 50) }
        let groupB = (0..<60).map { venue(id: "b\($0)", lat: 0.6 * cell, lng: lngFixed, score: 50) }

        let built = MapAnnotationPlanner.clusters(for: groupA + groupB, spanLongitude: spanLongitude)
        #expect(built.count == 1, "test setup: the coarse grid must collapse both groups into one cell")

        let subdivided = MapAnnotationPlanner.subdivideOversized(
            built,
            sourceVenues: groupA + groupB,
            cellDegrees: cell,
            visibleCount: groupA.count + groupB.count
        )
        #expect(subdivided.count > 1, "an oversized cell must split")
        #expect(subdivided.reduce(0) { $0 + $1.count } == groupA.count + groupB.count, "subdividing must not drop venues")
    }

    @Test func subdivideKeepsAnOversizedClusterWhenTheFinerGridCannotSplitIt() {
        // Every venue at the exact same coordinate: halving the cell still
        // buckets them together, so the guard must keep the single oversized
        // cluster rather than looping or dropping venues.
        let venues = (0..<50).map { venue(id: "same\($0)", lat: 40.7359, lng: -73.9911, score: 50) }
        let cell = MapAnnotationPlanner.clusterCellDegrees(spanLongitude: 0.035)
        let built = MapAnnotationPlanner.clusters(for: venues, spanLongitude: 0.035)
        #expect(built.count == 1)

        let subdivided = MapAnnotationPlanner.subdivideOversized(
            built, sourceVenues: venues, cellDegrees: cell, visibleCount: venues.count
        )
        #expect(subdivided.count == 1, "an unsplittable cell must be kept, not dropped or looped on")
        #expect(subdivided.first?.count == 50)
    }

    // MARK: - bd#204: declutter (pin vs. cluster overlap)

    @Test func declutterMovesAClusterAwayFromAnOverlappingPin() {
        let pin = venue(id: "pin", lat: 40.7359, lng: -73.9911, score: 95)
        let cellDegrees = 0.01
        let overlapping = VenueCluster(id: "c1", latitude: 40.7359, longitude: -73.9911, count: 10, bestScore: 70, hasObservedVenue: true)
        let farAway = VenueCluster(id: "c2", latitude: 40.80, longitude: -74.05, count: 10, bestScore: 70, hasObservedVenue: true)

        let result = MapAnnotationPlanner.declutter([overlapping, farAway], against: [pin], cellDegrees: cellDegrees)
        let movedOverlap = result.first { $0.id == "c1" }!
        let untouchedFar = result.first { $0.id == "c2" }!

        #expect(movedOverlap.latitude != overlapping.latitude || movedOverlap.longitude != overlapping.longitude)
        #expect(untouchedFar.latitude == farAway.latitude && untouchedFar.longitude == farAway.longitude)
        // Never drops or renames the cluster, and never changes its count.
        #expect(movedOverlap.count == overlapping.count)
    }

    @Test func fullDatasetScaleUsesAllThreeLayersRatherThanCollapsingToAHandful() {
        // The #54 pathology was per-venue annotations at dataset scale; the
        // bd#204 pathology was the opposite — near-everything collapsing
        // into a handful of giant bubbles. The fix sits in between: evidence
        // stays visible as pins/dots, only genuine overflow clusters, and no
        // cluster dominates the viewport.
        let venues = grid(count: 2_180, extent: 0.12)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: region())
        let visible = MapAnnotationPlanner.candidates(venues: venues, region: region())

        #expect(plan.pins.count == min(MapAnnotationPlanner.pinLimit, visible.filter(\.isObserved).count))
        #expect(plan.dots.count <= MapAnnotationPlanner.dotBudget)
        for cluster in plan.clusters {
            #expect(Double(cluster.count) <= Double(visible.count) * MapAnnotationPlanner.maxClusterShare + 0.001)
        }
    }

    @Test func offscreenVenuesNeverForceClustering() {
        // 600 venues far away + 3 nearby: the viewport only sees 3 ⇒ pins.
        let far = grid(count: 600, centerLat: 40.9, centerLng: -73.7, extent: 0.02)
        let near = grid(count: 3)
        let plan = MapAnnotationPlanner.plan(venues: far + near, region: region())
        #expect(plan.pins.count == 3)
        #expect(plan.dots.isEmpty)
        #expect(plan.clusters.isEmpty)
    }

    // MARK: - bd#204: determinism

    @Test func planIsDeterministicForTheSameInput() {
        let venues = grid(count: 400)
        let r = region()
        let first = MapAnnotationPlanner.plan(venues: venues, region: r)
        let second = MapAnnotationPlanner.plan(venues: venues, region: r)
        #expect(first == second)
    }

    // MARK: - Clusters (grid mechanics, unaffected by the bd#204 guard)

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

    // MARK: - Stale/unknown region fallback (brewdesk#157)

    @Test func planFallsBackToUnculledVenuesWhenRegionIsUnknown() {
        // No camera has settled yet (cold start, or every `MapProxy`
        // conversion has failed) — a nil region must plan against every
        // venue, never an empty list.
        let venues = grid(count: 10)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: nil)
        #expect(Set(plan.pins.map(\.id)) == Set(venues.map(\.id)))
    }

    @Test func planFallsBackToUnculledVenuesWhenTheKnownRegionExcludesEveryVenue() {
        // A region that legitimately covers none of the venues (stale after
        // a search clear, a filter change, or a locate-button move with no
        // gesture to trigger a re-plan) must not render as zero pins while
        // venues exist — brewdesk#157's core symptom.
        let venues = grid(count: 10)
        let staleRegion = region(lat: 41.5, lng: -74.5, span: 0.01)
        #expect(MapAnnotationPlanner.culled(venues, region: staleRegion).isEmpty, "test setup: region must exclude every venue")

        let plan = MapAnnotationPlanner.plan(venues: venues, region: staleRegion)
        #expect(Set(plan.pins.map(\.id)) == Set(venues.map(\.id)))
    }

    @Test func planNeverFallsBackWhenTheRegionGenuinelyHasNoVenues() {
        // An empty `venues` input (e.g. a genuinely empty dataset) must stay
        // empty — the fallback only rescues a non-empty list a bad region
        // culled to nothing, never an honest zero.
        let plan = MapAnnotationPlanner.plan(venues: [], region: region())
        #expect(plan.pins.isEmpty)
        #expect(plan.dots.isEmpty)
        #expect(plan.clusters.isEmpty)
    }

    // MARK: - Plan helpers

    @Test func planKnowsWhichVenuesItRendersIndividually() {
        let venues = grid(count: 10)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: region())
        #expect(plan.containsVenue(id: venues[0].id))
        #expect(!plan.containsVenue(id: "absent"))

        let dense = grid(count: MapAnnotationPlanner.pinLimit + MapAnnotationPlanner.dotBudget + 200)
        let densePlan = MapAnnotationPlanner.plan(venues: dense, region: region())
        #expect(!densePlan.containsVenue(id: "absent"), "clusters render no individual venue")
    }
}
