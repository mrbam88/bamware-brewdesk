import Foundation
import MapKit
import Testing
import VenueKit
@testable import BrewDeskKit

/// Marker planning for the map (brewdesk#54, re-shaped bd#204/#209,
/// replaced outright by bd#212's "micro teardrops" — no cluster/stack
/// grouping of any kind remains; every venue plans its OWN marker, sized by
/// zoom and demoted to a small dot only on a genuine screen-space collision
/// with a better-scored marker).
struct MapAnnotationPlannerTests {

    // MARK: - Helpers

    private let mapSize = CGSize(width: 390, height: 660)
    /// A large virtual canvas so a fixed-degree step between venues is also
    /// a large-enough pixel step to stay collision-free regardless of
    /// marker size at the region's span.
    private let wideMapSize = CGSize(width: 2_400, height: 2_400)

    private func venue(id: String, lat: Double, lng: Double, score: Int = 50, observed: Bool = true) -> Venue {
        let observedAt = "2026-08-01T00:00:00Z"
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

    /// `count` venues spread evenly inside the given box — dense enough to
    /// exercise collision handling.
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

    /// A grid spaced far enough apart, at the given span/mapSize, that no
    /// two footprints can ever collide.
    private func wellSeparatedGrid(
        count: Int, step: Double, centerLat: Double = 40.7359, centerLng: Double = -73.9911,
        observed: Bool = true, scoreOffset: Int = 0
    ) -> [Venue] {
        let columns = Int(Double(count).squareRoot().rounded(.up))
        return (0..<count).map { index in
            venue(
                id: "s\(index)",
                lat: centerLat - Double(columns) * step / 2 + Double(index / columns) * step,
                lng: centerLng - Double(columns) * step / 2 + Double(index % columns) * step,
                score: scoreOffset + (index * 37) % 101,
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

    /// Every footprint `plan` would draw, in the same screen space
    /// `MapAnnotationPlanner.plan` used internally.
    private func footprints(for plan: MapAnnotationPlan, region: MKCoordinateRegion, mapSize: CGSize) -> [AABB] {
        let projector = ScreenProjector(region: region, size: mapSize)
        return plan.markers.map {
            MapAnnotationPlanner.footprint(diameter: $0.kind.diameter, at: projector.point(for: coordinate(of: $0.venue)))
        }
    }

    private func coordinate(of venue: Venue) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: venue.lat, longitude: venue.lng)
    }

    private func assertNoOverlaps(_ boxes: [AABB], sourceLocation: SourceLocation = #_sourceLocation) {
        guard boxes.count > 1 else { return }
        for i in 0..<(boxes.count - 1) {
            for j in (i + 1)..<boxes.count {
                #expect(!boxes[i].intersects(boxes[j]), "markers \(i) and \(j) overlap", sourceLocation: sourceLocation)
            }
        }
    }

    // MARK: - Culling (unchanged from bd#209/#210)

    @Test func cullingKeepsVenuesInsideRegionAndMargin() {
        let inside = venue(id: "inside", lat: 40.7359, lng: -73.9911)
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

    // MARK: - bd#212: zoom-driven size

    @Test func headDiameterClampsAtBothEndsAndInterpolatesBetweenStops() {
        #expect(MapAnnotationPlanner.headDiameter(forLongitudeSpan: 0.09) == 4, "zoomed out clamps at the 4pt floor")
        #expect(MapAnnotationPlanner.headDiameter(forLongitudeSpan: 0.045) == 4)
        #expect(MapAnnotationPlanner.headDiameter(forLongitudeSpan: 0.022) == 12)
        #expect(MapAnnotationPlanner.headDiameter(forLongitudeSpan: 0.011) == 17)
        #expect(MapAnnotationPlanner.headDiameter(forLongitudeSpan: 0.005) == 20)
        #expect(MapAnnotationPlanner.headDiameter(forLongitudeSpan: 0.001) == 20, "closer than the closest stop clamps at the 20pt ceiling")
        // Midpoint between two stops lands strictly between their diameters.
        let mid = MapAnnotationPlanner.headDiameter(forLongitudeSpan: (0.045 + 0.022) / 2)
        #expect(mid > 4 && mid < 12)
    }

    @Test func headDiameterIsMonotonicAsSpanShrinks() {
        let spans = stride(from: 0.06, through: 0.003, by: -0.001).map { $0 }
        var previous: CGFloat = 0
        for span in spans {
            let diameter = MapAnnotationPlanner.headDiameter(forLongitudeSpan: span)
            #expect(diameter >= previous, "diameter must never shrink as the map zooms IN (span \(span))")
            previous = diameter
        }
    }

    @Test func speckDiameterIsZeroWhenZoomedOutAndCapsAtThreePoints() {
        #expect(MapAnnotationPlanner.speckDiameter(forLongitudeSpan: 0.045) == 0)
        #expect(MapAnnotationPlanner.speckDiameter(forLongitudeSpan: 0.09) == 0)
        #expect(MapAnnotationPlanner.speckDiameter(forLongitudeSpan: 0.022) == 2)
        #expect(MapAnnotationPlanner.speckDiameter(forLongitudeSpan: 0.011) == 3)
        #expect(MapAnnotationPlanner.speckDiameter(forLongitudeSpan: 0.002) == 3, "clamps at the 3pt ceiling")
    }

    // MARK: - bd#212: collision-free placement

    @Test func wellSeparatedRatedVenuesAllRenderAsFullTeardropsWithNumbers() {
        // Street-zoom span (0.011 ⇒ 17pt heads, well above both the shape
        // and number thresholds); a generous step keeps every footprint
        // collision-free.
        let venues = wellSeparatedGrid(count: 30, step: 0.0015)
        let testRegion = region(span: 0.011)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: wideMapSize)
        #expect(plan.markers.count == 30)
        for marker in plan.markers {
            guard case .teardrop = marker.kind else {
                Issue.record("expected a teardrop, got \(marker.kind) for \(marker.id)")
                continue
            }
            #expect(marker.showsNumber, "a 17pt un-demoted teardrop must show its number")
        }
        assertNoOverlaps(footprints(for: plan, region: testRegion, mapSize: wideMapSize))
    }

    @Test func denselyPackedCandidatesDemoteToDotsInsteadOfOverlapping() {
        // Two observed venues close enough that their TEARDROP footprints
        // collide at street zoom (19.2pt apart, under the 21.7pt combined
        // teardrop half-heights), but far enough that a demoted dot (42% of
        // 17pt ≈ 7.1pt) does not (19.2pt clears the 16.3pt combined
        // teardrop+dot half-heights).
        let testRegion = region(span: 0.011)
        let a = venue(id: "a", lat: 40.7359, lng: -73.9911, score: 90)
        let b = venue(id: "b", lat: 40.7359 + 0.00032, lng: -73.9911, score: 88)
        let plan = MapAnnotationPlanner.plan(venues: [a, b], region: testRegion, mapSize: mapSize)
        #expect(plan.markers.count == 2, "the loser must still render, demoted, not vanish")
        let winner = plan.markers.first { $0.id == "a" }
        let loser = plan.markers.first { $0.id == "b" }
        guard case .teardrop = winner?.kind else { Issue.record("higher-scored venue must win the teardrop"); return }
        guard case .dot = loser?.kind else { Issue.record("lower-scored venue must be demoted to a dot"); return }
        #expect(loser?.showsNumber == false, "a demoted dot never shows a number")
        assertNoOverlaps(footprints(for: plan, region: testRegion, mapSize: mapSize))
    }

    @Test func extremelyDenseCollisionCanDropAVenueRatherThanOverlap() {
        // 40 observed venues crammed into a tiny box at the largest (20pt)
        // marker size — even the demoted-dot fallback runs out of room for
        // some of them. The hard invariant is "never overlap," not "never
        // drop."
        let venues = grid(count: 40, extent: 0.0006, observed: true)
        let testRegion = region(span: 0.004)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize)
        assertNoOverlaps(footprints(for: plan, region: testRegion, mapSize: mapSize))
        #expect(plan.markers.count <= 40)
    }

    @Test func selectedVenueAlwaysPlacedAtFixedSizeAndReservesItsFootprint() {
        let testRegion = region(span: 0.011)
        let a = venue(id: "a", lat: 40.7359, lng: -73.9911, score: 50)
        // Deliberately near-identical coordinates and a HIGHER score than
        // the selected venue — without the seeding pass this would normally
        // out-rank "a" for the marker slot.
        let b = venue(id: "b", lat: 40.735901, lng: -73.991101, score: 95)
        let plan = MapAnnotationPlanner.plan(venues: [a, b], region: testRegion, mapSize: mapSize, selectedVenueID: "a")
        let selectedMarker = plan.markers.first { $0.id == "a" }
        #expect(selectedMarker?.isSelected == true)
        #expect(selectedMarker?.kind.diameter == MapAnnotationPlanner.selectedDiameter)
        #expect(!plan.markers.contains { $0.id == "b" }, "nothing may overlap the selected venue's reserved footprint")
        assertNoOverlaps(footprints(for: plan, region: testRegion, mapSize: mapSize))
    }

    @Test func totalAnnotationsNeverExceedTheCapAtExtremeDensity() {
        let venues = grid(count: 2_000, extent: 0.02)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: region(), mapSize: mapSize)
        #expect(plan.annotationCount <= MapAnnotationPlanner.maxAnnotations)
        assertNoOverlaps(footprints(for: plan, region: region(), mapSize: mapSize))
    }

    // MARK: - bd#159/#212: unrated venues are specks, never numbered

    @Test func unratedVenuesNeverShowANumberOrCompeteWithRatedPlacement() {
        let unrated = grid(count: 200, extent: 0.02, observed: false)
        let rated = wellSeparatedGrid(count: 5, step: 0.003, observed: true, scoreOffset: 90)
        let testRegion = region(span: 0.011)
        let plan = MapAnnotationPlanner.plan(venues: unrated + rated, region: testRegion, mapSize: wideMapSize)
        let ratedIDs = Set(rated.map(\.id))
        for marker in plan.markers where !ratedIDs.contains(marker.id) {
            #expect(!marker.showsNumber, "an unrated venue must never show a number")
            guard case .speck = marker.kind else {
                Issue.record("unrated venue \(marker.id) must render as a speck, got \(marker.kind)")
                continue
            }
        }
        for marker in plan.markers where ratedIDs.contains(marker.id) {
            #expect(marker.showsNumber, "a well-separated rated venue at street zoom must show its number")
        }
        assertNoOverlaps(footprints(for: plan, region: testRegion, mapSize: wideMapSize))
    }

    @Test func noSpecksRenderWhenZoomedAllTheWayOut() {
        let unrated = grid(count: 50, extent: 0.02, observed: false)
        let testRegion = region(span: 0.05)
        let plan = MapAnnotationPlanner.plan(venues: unrated, region: testRegion, mapSize: mapSize)
        #expect(plan.markers.isEmpty, "unrated venues draw nothing at the widest zoom (0pt speck)")
    }

    @Test func ratedBudgetIsSpentBeforeUnratedSpecks() {
        // Rated venues alone exceed the cap; no speck should ever squeeze in
        // ahead of a rated marker.
        let rated = grid(count: MapAnnotationPlanner.maxAnnotations + 50, extent: 0.02, observed: true)
        let unrated = grid(count: 30, centerLat: 40.74, centerLng: -73.98, extent: 0.005, observed: false)
        let testRegion = region(span: 0.03)
        let plan = MapAnnotationPlanner.plan(venues: rated + unrated, region: testRegion, mapSize: mapSize)
        #expect(plan.annotationCount <= MapAnnotationPlanner.maxAnnotations)
        #expect(plan.markers.allSatisfy { $0.venue.isObserved }, "no unrated speck should have taken a slot from a rated venue")
    }

    // MARK: - bd#210: chrome exclusion rects (kept unchanged from #209/#210)

    @Test func noPlacedMarkerIntersectsAnExclusionRect() {
        let testRegion = region()
        let exclusions = [
            CGRect(x: 0, y: 0, width: mapSize.width, height: 140),
            CGRect(x: mapSize.width - 80, y: mapSize.height - 140, width: 68, height: 68),
        ]
        let venues = grid(count: 400, extent: 0.03)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize, exclusionRects: exclusions)

        let exclusionBoxes = exclusions.map { AABB(minX: $0.minX, maxX: $0.maxX, minY: $0.minY, maxY: $0.maxY) }
        for box in footprints(for: plan, region: testRegion, mapSize: mapSize) {
            for exclusion in exclusionBoxes {
                #expect(!box.intersects(exclusion), "a marker sits under an exclusion rect")
            }
        }
        assertNoOverlaps(footprints(for: plan, region: testRegion, mapSize: mapSize))
    }

    @Test func markerUnderAnExclusionRectDemotesToADotWhenTheDotFootprintClears() {
        let testRegion = region(span: 0.011)
        let projector = ScreenProjector(region: testRegion, size: mapSize)
        let target = venue(id: "under-chrome", lat: 40.7359, lng: -73.9911, score: 90)
        let point = projector.point(for: CLLocationCoordinate2D(latitude: target.lat, longitude: target.lng))
        // Offset (not centered) exclusion, mirroring bd#210's own original
        // fixture: its right edge sits at point.x-7 — inside the 17pt
        // teardrop's 10pt half-width (so the full teardrop collides) but
        // outside the demoted (~7.1pt) dot's 5.1pt half-width (so the dot
        // clears once demoted).
        let exclusion = CGRect(x: point.x - 100, y: point.y - 50, width: 93, height: 100)
        let plan = MapAnnotationPlanner.plan(venues: [target], region: testRegion, mapSize: mapSize, exclusionRects: [exclusion])
        guard let marker = plan.markers.first else {
            Issue.record("expected the venue to demote, not vanish")
            return
        }
        guard case .dot = marker.kind else {
            Issue.record("expected a demoted dot, got \(marker.kind)")
            return
        }
    }

    @Test func markerFullyInsideAnExclusionRectWithNoRoomNearbyIsSkipped() {
        let testRegion = region(span: 0.011)
        let projector = ScreenProjector(region: testRegion, size: mapSize)
        let target = venue(id: "chrome-dot", lat: 40.7360, lng: -73.9912, score: 10, observed: true)
        let point = projector.point(for: CLLocationCoordinate2D(latitude: target.lat, longitude: target.lng))
        let exclusion = CGRect(x: point.x - 40, y: point.y - 40, width: 80, height: 80)
        let plan = MapAnnotationPlanner.plan(venues: [target], region: testRegion, mapSize: mapSize, exclusionRects: [exclusion])
        #expect(plan.annotationCount == 0, "a lone venue fully under chrome, with nowhere to fit even demoted, must not render")
    }

    @Test func planWithExclusionRectsStaysDeterministic() {
        let testRegion = region()
        let exclusions = [CGRect(x: 0, y: 0, width: mapSize.width, height: 140)]
        let venues = grid(count: 400, extent: 0.03)
        let first = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize, exclusionRects: exclusions)
        let second = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize, exclusionRects: exclusions)
        #expect(first == second)
        #expect(first.annotationCount <= MapAnnotationPlanner.maxAnnotations)
    }

    // MARK: - bd#212: determinism and stable ids

    @Test func planIsDeterministicForTheSameInput() {
        let venues = grid(count: 400)
        let r = region()
        let first = MapAnnotationPlanner.plan(venues: venues, region: r, mapSize: mapSize)
        let second = MapAnnotationPlanner.plan(venues: venues, region: r, mapSize: mapSize)
        #expect(first == second)
    }

    /// bd#212 perf requirement: "100% of ids unchanged for a pan that keeps
    /// the same venues in the fetched set." A pan of one meter at street
    /// zoom keeps the exact same culled venue set and the exact same
    /// per-marker screen-space outcome, so the marker id set — and each
    /// marker's kind — must come back byte-identical.
    @Test func stableIDsAcrossATinyPanThatKeepsTheSameVenues() {
        let venues = wellSeparatedGrid(count: 40, step: 0.0015)
        let before = MapAnnotationPlanner.plan(venues: venues, region: region(span: 0.011), mapSize: wideMapSize)
        let nudged = region(lat: 40.7359 + 0.0000005, lng: -73.9911, span: 0.011)
        let after = MapAnnotationPlanner.plan(venues: venues, region: nudged, mapSize: wideMapSize)
        #expect(Set(before.markers.map(\.id)) == Set(after.markers.map(\.id)), "an imperceptible pan must not change which venues are drawn")
        let beforeKinds = Dictionary(uniqueKeysWithValues: before.markers.map { ($0.id, $0.kind) })
        for marker in after.markers {
            #expect(beforeKinds[marker.id] == marker.kind, "an imperceptible pan must not change a venue's marker kind")
        }
    }

    // MARK: - bd#212: 500-random-venue property test (VERIFY step of the ticket)

    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    private func randomVenues(count: Int, seed: UInt64, centerLat: Double, centerLng: Double, extent: Double) -> [Venue] {
        var rng = SeededGenerator(seed: seed)
        return (0..<count).map { index in
            let dLat = Double.random(in: -extent / 2...extent / 2, using: &rng)
            let dLng = Double.random(in: -extent / 2...extent / 2, using: &rng)
            let score = Int.random(in: 0...100, using: &rng)
            let observed = Double.random(in: 0...1, using: &rng) < 0.7
            return venue(id: "r\(index)", lat: centerLat + dLat, lng: centerLng + dLng, score: score, observed: observed)
        }
    }

    @Test func fiveHundredRandomVenuesInADenseBoundingBoxProduceACollisionFreeDeterministicPlan() {
        let venues = randomVenues(count: 500, seed: 42, centerLat: 40.7335, centerLng: -74.0027, extent: 0.02)
        let testRegion = region(lat: 40.7335, lng: -74.0027, span: 0.02)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize)

        // Zero intersecting footprints, anywhere in the rendered plan.
        assertNoOverlaps(footprints(for: plan, region: testRegion, mapSize: mapSize))

        // Total rendered annotations never exceed the cap.
        #expect(plan.annotationCount <= MapAnnotationPlanner.maxAnnotations)

        // Every marker corresponds to a real input venue, never a duplicate.
        #expect(plan.markers.map(\.id).count == Set(plan.markers.map(\.id)).count, "no venue may be drawn twice")

        // A demoted or full RATED marker is only ever drawn for an observed
        // venue; only an unrated venue ever renders as a speck.
        for marker in plan.markers {
            switch marker.kind {
            case .teardrop, .dot: #expect(marker.venue.isObserved)
            case .speck: #expect(!marker.venue.isObserved)
            }
        }

        // Deterministic: replanning the identical input yields an identical
        // plan.
        let replanned = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize)
        #expect(plan == replanned)
    }

    // MARK: - Stale/unknown region fallback (brewdesk#157)

    @Test func planFallsBackToUnculledVenuesWhenRegionIsUnknown() {
        let venues = grid(count: 10)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: nil, mapSize: mapSize)
        #expect(Set(plan.markers.map(\.id)) == Set(venues.map(\.id)))
        #expect(plan.markers.allSatisfy { $0.kind.diameter == MapAnnotationPlanner.headDiameter(forLongitudeSpan: 0.005) })
    }

    @Test func planFallsBackWithoutLosingVenuesWhenTheKnownRegionExcludesEveryVenue() {
        let venues = grid(count: 10)
        let staleRegion = region(lat: 41.5, lng: -74.5, span: 0.01)
        #expect(MapAnnotationPlanner.culled(venues, region: staleRegion).isEmpty, "test setup: region must exclude every venue")

        let plan = MapAnnotationPlanner.plan(venues: venues, region: staleRegion, mapSize: mapSize)
        #expect(plan.markers.count == venues.count, "no venue may silently vanish just because the region is stale")
        assertNoOverlaps(footprints(for: plan, region: staleRegion, mapSize: mapSize))
    }

    @Test func planNeverFallsBackWhenTheRegionGenuinelyHasNoVenues() {
        let plan = MapAnnotationPlanner.plan(venues: [], region: region(), mapSize: mapSize)
        #expect(plan.markers.isEmpty)
    }

    // MARK: - Plan helpers

    @Test func planKnowsWhichVenuesItRendersIndividually() {
        let venues = grid(count: 10)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: region(), mapSize: mapSize)
        #expect(plan.containsVenue(id: venues[0].id))
        #expect(!plan.containsVenue(id: "absent"))
    }

    // MARK: - Re-plan hysteresis (CafeMapScreen, unchanged from #209)

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
}
