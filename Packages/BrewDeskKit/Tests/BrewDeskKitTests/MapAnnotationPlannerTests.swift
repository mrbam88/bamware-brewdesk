import Foundation
import MapKit
import Testing
import VenueKit
@testable import BrewDeskKit

/// Marker planning for the map (brewdesk#54, re-shaped bd#204/#209,
/// replaced outright by bd#212's "micro teardrops" — no cluster/stack
/// grouping of any kind remains; every venue plans its OWN marker, sized by
/// the settled camera's real metres-per-screen-point (supervisor review:
/// keying off the requested region's raw degree span didn't survive the
/// phone's actual aspect ratio), and demoted to a small dot only on a
/// genuine screen-space collision with a better-scored teardrop).
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

    /// A grid spaced far enough apart, at the given step/mapSize, that no
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

    /// A region whose longitude span resolves to approximately the given
    /// metres-per-point at `mapSize`'s width and the region's own latitude
    /// — lets tests reason directly in the unit the planner actually sizes
    /// from, instead of back-solving a span by hand.
    private func region(forMetersPerPoint mpp: Double, mapWidth: CGFloat, lat: Double = 40.7335, lng: Double = -74.0027) -> MKCoordinateRegion {
        let metersPerDegreeLng = 111_320.0 * cos(lat * .pi / 180)
        let span = mpp * Double(mapWidth) / metersPerDegreeLng
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
    }

    private func coordinate(of venue: Venue) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: venue.lat, longitude: venue.lng)
    }

    /// Every TEARDROP footprint `plan` would draw, in the same screen space
    /// `MapAnnotationPlanner.plan` used internally — `.dot`/`.speck` are
    /// native `MapCircle` overlays with no discrete screen-space footprint
    /// to collide-check any more (see the planner's own doc comments).
    private func teardropFootprints(for plan: MapAnnotationPlan, region: MKCoordinateRegion, mapSize: CGSize) -> [AABB] {
        let projector = ScreenProjector(region: region, size: mapSize)
        return plan.teardrops.compactMap { placement in
            guard let diameter = placement.kind.teardropDiameter else { return nil }
            return MapAnnotationPlanner.teardropFootprint(diameter: diameter, at: projector.point(for: coordinate(of: placement.venue)))
        }
    }

    private func assertNoOverlaps(_ boxes: [AABB], sourceLocation: SourceLocation = #_sourceLocation) {
        guard boxes.count > 1 else { return }
        for i in 0..<(boxes.count - 1) {
            for j in (i + 1)..<boxes.count {
                #expect(!boxes[i].intersects(boxes[j]), "teardrops \(i) and \(j) overlap", sourceLocation: sourceLocation)
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

    // MARK: - bd#212 (supervisor revision): metres-per-point sizing

    @Test func headDiameterClampsAtBothEndsAndInterpolatesBetweenStops() {
        #expect(MapAnnotationPlanner.headDiameter(forMetersPerPoint: 20) == 4, "zoomed out clamps at the 4pt floor")
        #expect(MapAnnotationPlanner.headDiameter(forMetersPerPoint: 9.0) == 4)
        #expect(MapAnnotationPlanner.headDiameter(forMetersPerPoint: 5.4) == 11.5, "numbers (>= 11 pt) hold through a normal neighborhood view")
        #expect(MapAnnotationPlanner.headDiameter(forMetersPerPoint: 3.6) == 12.5)
        #expect(MapAnnotationPlanner.headDiameter(forMetersPerPoint: 1.8) == 17)
        #expect(MapAnnotationPlanner.headDiameter(forMetersPerPoint: 0.9) == 20)
        #expect(MapAnnotationPlanner.headDiameter(forMetersPerPoint: 0.1) == 20, "closer than the closest stop clamps at the 20pt ceiling")
        // Midpoint (on the LOG scale) between two stops lands strictly
        // between their diameters.
        let midMPP = (9.0 * 5.4).squareRoot()
        let mid = MapAnnotationPlanner.headDiameter(forMetersPerPoint: midMPP)
        #expect(mid > 4 && mid < 12)
    }

    @Test func headDiameterIsMonotonicAsMetersPerPointShrinks() {
        var previous: CGFloat = 0
        var mpp = 10.0
        while mpp >= 0.5 {
            let diameter = MapAnnotationPlanner.headDiameter(forMetersPerPoint: mpp)
            #expect(diameter >= previous, "diameter must never shrink as the map zooms IN (mpp \(mpp))")
            previous = diameter
            mpp -= 0.2
        }
    }

    @Test func metersPerPointReflectsRealVisibleWidthNotRawDegreeSpan() {
        // Same span (same real-world visible width) spread across a WIDER
        // map means each point covers LESS real-world distance — metres/
        // point must shrink as the map gets wider, not grow. This is the
        // exact aspect-ratio sensitivity the raw-span approach missed: two
        // devices requesting the identical region span render different
        // metres/point once MapKit fits it to each one's actual width.
        let testRegion = region(span: 0.02)
        let narrow = MapAnnotationPlanner.metersPerPoint(region: testRegion, mapWidth: 300)
        let wide = MapAnnotationPlanner.metersPerPoint(region: testRegion, mapWidth: 600)
        #expect(wide < narrow)
        #expect(narrow / wide > 1.9 && narrow / wide < 2.1, "doubling the map width should roughly halve metres/point for the same span")
    }

    // MARK: - bd#212: collision-free teardrop placement

    @Test func wellSeparatedRatedVenuesAllRenderAsFullTeardropsWithNumbers() {
        // 1.8 m/pt ⇒ 17pt heads, well above both the shape and number
        // thresholds; a generous step keeps every footprint collision-free.
        let venues = wellSeparatedGrid(count: 30, step: 0.0015)
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: wideMapSize.width)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: wideMapSize)
        #expect(plan.markers.count == 30)
        #expect(plan.teardrops.count == 30)
        #expect(plan.dots.isEmpty)
        for marker in plan.teardrops {
            #expect(marker.showsNumber, "a 17pt un-demoted teardrop must show its number")
        }
        assertNoOverlaps(teardropFootprints(for: plan, region: testRegion, mapSize: wideMapSize))
    }

    @Test func denselyPackedCandidatesDemoteToDotsInsteadOfOverlapping() {
        // Two observed venues close enough that their TEARDROP footprints
        // (17+2=19pt side, half 9.5) collide, but the tight "head diameter +
        // 1pt, tail excluded" box means only genuinely overlapping heads
        // ever demote.
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: mapSize.width)
        let a = venue(id: "a", lat: 40.7335, lng: -74.0027, score: 90)
        let b = venue(id: "b", lat: 40.7335 + 0.00006, lng: -74.0027, score: 88)
        let plan = MapAnnotationPlanner.plan(venues: [a, b], region: testRegion, mapSize: mapSize)
        #expect(plan.markers.count == 2, "the loser must still render, demoted, not vanish")
        #expect(plan.teardrops.contains { $0.id == "a" }, "higher-scored venue must win the teardrop")
        #expect(plan.dots.contains { $0.id == "b" }, "lower-scored venue must be demoted to a dot")
        let loser = plan.markers.first { $0.id == "b" }
        #expect(loser?.showsNumber == false, "a demoted dot never shows a number")
        assertNoOverlaps(teardropFootprints(for: plan, region: testRegion, mapSize: mapSize))
    }

    @Test func wellSeparatedVenuesNeverDemoteEvenAtRealisticCafeDensity() {
        // Regression for the supervisor's hood-zoom finding: at 3.6 m/pt a
        // 12pt head's footprint (12+1·2=14pt side) needs >14·3.6≈50.4m of
        // real-world clearance on at least one axis to stay collision-free.
        // 70m apart clears that with margin on both lat AND lng (using the
        // LONGITUDE metres-per-degree, the smaller of the two at this
        // latitude, so the same degree-step is >=70m on both axes).
        let lat = 40.7335
        let metersApart = 70.0
        let metersPerDegreeLng = 111_320.0 * cos(lat * .pi / 180)
        let stepDegrees = metersApart / metersPerDegreeLng
        let venues = wellSeparatedGrid(count: 20, step: stepDegrees, centerLat: lat, centerLng: -74.0027, observed: true)
        let testRegion = region(forMetersPerPoint: 3.6, mapWidth: mapSize.width, lat: lat, lng: -74.0027)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize)
        #expect(plan.teardrops.count == 20, "70m-separated venues at 3.6 m/pt (12pt heads) must not demote")
        assertNoOverlaps(teardropFootprints(for: plan, region: testRegion, mapSize: mapSize))
    }

    @Test func belowShapeThresholdEveryRatedVenueIsADotWithNoCollisionWork() {
        // 20 m/pt is past the 7.2 m/pt floor — every rated venue renders as
        // a dot, none even attempt a teardrop, so density here can't demote
        // anything (there's nothing left to demote).
        let venues = grid(count: 40, extent: 0.002, observed: true)
        let testRegion = region(forMetersPerPoint: 20, mapWidth: mapSize.width)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize)
        #expect(plan.teardrops.isEmpty)
        #expect(plan.dots.count == plan.markers.count)
    }

    @Test func selectedVenueAlwaysPlacedAtFixedSizeAndReservesItsFootprint() {
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: mapSize.width)
        let a = venue(id: "a", lat: 40.7335, lng: -74.0027, score: 50)
        // Deliberately near-identical coordinates and a HIGHER score than
        // the selected venue — without the seeding pass this would normally
        // out-rank "a" for the marker slot.
        let b = venue(id: "b", lat: 40.733501, lng: -74.002701, score: 95)
        let plan = MapAnnotationPlanner.plan(venues: [a, b], region: testRegion, mapSize: mapSize, selectedVenueID: "a")
        let selectedMarker = plan.markers.first { $0.id == "a" }
        #expect(selectedMarker?.isSelected == true)
        #expect(selectedMarker?.kind.teardropDiameter == MapAnnotationPlanner.selectedDiameter)
        #expect(!plan.teardrops.contains { $0.id == "b" }, "nothing may overlap the selected venue's reserved footprint")
        assertNoOverlaps(teardropFootprints(for: plan, region: testRegion, mapSize: mapSize))
    }

    @Test func totalAnnotationsNeverExceedTheCapAtExtremeDensity() {
        let venues = grid(count: 2_000, extent: 0.02)
        let testRegion = region(forMetersPerPoint: 3.6, mapWidth: mapSize.width)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize)
        #expect(plan.annotationCount <= MapAnnotationPlanner.maxAnnotations)
        assertNoOverlaps(teardropFootprints(for: plan, region: testRegion, mapSize: mapSize))
    }

    // MARK: - bd#159/#212: unrated venues are specks, never numbered

    @Test func unratedVenuesAreSpecksAndNeverShowANumberOrCompeteWithRatedPlacement() {
        let unrated = grid(count: 200, extent: 0.02, observed: false)
        let rated = wellSeparatedGrid(count: 5, step: 0.003, observed: true, scoreOffset: 90)
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: wideMapSize.width)
        let plan = MapAnnotationPlanner.plan(venues: unrated + rated, region: testRegion, mapSize: wideMapSize)
        let ratedIDs = Set(rated.map(\.id))
        #expect(plan.specks.allSatisfy { !ratedIDs.contains($0.id) })
        #expect(plan.specks.allSatisfy { !$0.showsNumber })
        for marker in plan.markers where ratedIDs.contains(marker.id) {
            #expect(marker.showsNumber, "a well-separated rated venue at 1.8 m/pt must show its number")
        }
    }

    @Test func noSpecksRenderWhenZoomedAllTheWayOut() {
        let unrated = grid(count: 50, extent: 0.02, observed: false)
        let testRegion = region(forMetersPerPoint: 8, mapWidth: mapSize.width)
        let plan = MapAnnotationPlanner.plan(venues: unrated, region: testRegion, mapSize: mapSize)
        #expect(plan.markers.isEmpty, "unrated venues draw nothing beyond the 5 m/pt visibility threshold")
    }

    @Test func ratedBudgetIsSpentBeforeUnratedSpecks() {
        // Rated venues alone exceed the cap; no speck should ever squeeze in
        // ahead of a rated marker.
        let rated = grid(count: MapAnnotationPlanner.maxAnnotations + 50, extent: 0.02, observed: true)
        let unrated = grid(count: 30, centerLat: 40.74, centerLng: -73.98, extent: 0.005, observed: false)
        let testRegion = region(forMetersPerPoint: 3.6, mapWidth: mapSize.width)
        let plan = MapAnnotationPlanner.plan(venues: rated + unrated, region: testRegion, mapSize: mapSize)
        #expect(plan.annotationCount <= MapAnnotationPlanner.maxAnnotations)
        #expect(plan.markers.allSatisfy { $0.venue.isObserved }, "no unrated speck should have taken a slot from a rated venue")
    }

    // MARK: - bd#210: chrome exclusion rects (teardrops only, bd#212 revision)

    @Test func noPlacedTeardropIntersectsAnExclusionRect() {
        let testRegion = region(forMetersPerPoint: 3.6, mapWidth: mapSize.width)
        let exclusions = [
            CGRect(x: 0, y: 0, width: mapSize.width, height: 140),
            CGRect(x: mapSize.width - 80, y: mapSize.height - 140, width: 68, height: 68),
        ]
        let venues = grid(count: 400, extent: 0.03)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize, exclusionRects: exclusions)

        let exclusionBoxes = exclusions.map { AABB(minX: $0.minX, maxX: $0.maxX, minY: $0.minY, maxY: $0.maxY) }
        for box in teardropFootprints(for: plan, region: testRegion, mapSize: mapSize) {
            for exclusion in exclusionBoxes {
                #expect(!box.intersects(exclusion), "a teardrop sits under an exclusion rect")
            }
        }
        assertNoOverlaps(teardropFootprints(for: plan, region: testRegion, mapSize: mapSize))
    }

    @Test func teardropUnderAnExclusionRectDemotesToADot() {
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: mapSize.width)
        let projector = ScreenProjector(region: testRegion, size: mapSize)
        let target = venue(id: "under-chrome", lat: 40.7335, lng: -74.0027, score: 90)
        let point = projector.point(for: CLLocationCoordinate2D(latitude: target.lat, longitude: target.lng))
        let exclusion = CGRect(x: point.x - 20, y: point.y - 20, width: 40, height: 40)
        let plan = MapAnnotationPlanner.plan(venues: [target], region: testRegion, mapSize: mapSize, exclusionRects: [exclusion])
        #expect(plan.dots.map(\.id) == ["under-chrome"], "a teardrop under chrome demotes to a dot rather than vanishing")
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
    /// the same venues in the fetched set." A pan of a fraction of a metre
    /// keeps the exact same culled venue set and the exact same
    /// per-marker screen-space outcome, so the marker id set — and each
    /// marker's kind — must come back byte-identical.
    @Test func stableIDsAcrossATinyPanThatKeepsTheSameVenues() {
        let venues = wellSeparatedGrid(count: 40, step: 0.0015)
        // Comfortably inside the CLAMPED "closest" zone (<=0.9 m/pt always
        // returns exactly 20.0) so a sub-metre nudge in the region's
        // center can't tip a diameter across an interpolation boundary by
        // a floating-point hair — this test is about STABLE IDS/KINDS
        // across a pan, not about interpolation-boundary precision.
        let testRegion = region(forMetersPerPoint: 0.5, mapWidth: wideMapSize.width)
        let before = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: wideMapSize)
        var nudged = testRegion
        nudged.center.latitude += 0.0000005
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

        // Zero intersecting TEARDROP footprints, anywhere in the rendered plan.
        assertNoOverlaps(teardropFootprints(for: plan, region: testRegion, mapSize: mapSize))

        // Total rendered annotations never exceed the cap.
        #expect(plan.annotationCount <= MapAnnotationPlanner.maxAnnotations)

        // Every marker corresponds to a real input venue, never a duplicate.
        #expect(plan.markers.map(\.id).count == Set(plan.markers.map(\.id)).count, "no venue may be drawn twice")

        // A teardrop or dot is only ever drawn for an observed venue; only
        // an unrated venue ever renders as a speck.
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
        #expect(plan.teardrops.count == venues.count)
    }

    @Test func planFallsBackWithoutLosingVenuesWhenTheKnownRegionExcludesEveryVenue() {
        let venues = grid(count: 10)
        let staleRegion = region(lat: 41.5, lng: -74.5, span: 0.01)
        #expect(MapAnnotationPlanner.culled(venues, region: staleRegion).isEmpty, "test setup: region must exclude every venue")

        let plan = MapAnnotationPlanner.plan(venues: venues, region: staleRegion, mapSize: mapSize)
        #expect(plan.markers.count == venues.count, "no venue may silently vanish just because the region is stale")
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
