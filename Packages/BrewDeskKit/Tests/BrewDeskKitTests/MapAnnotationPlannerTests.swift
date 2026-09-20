import Foundation
import MapKit
import Testing
import VenueKit
@testable import BrewDeskKit

/// Representation planning for the map (brewdesk#54, re-shaped bd#204, made
/// collision-free bd#209): viewport culling, screen-space collision-free
/// pin/dot/stack placement, and stable grid clustering as the stack-
/// candidate source.
struct MapAnnotationPlannerTests {

    // MARK: - Helpers

    /// A realistic phone-portrait map viewport — every test below either
    /// passes this explicitly or relies on `MapAnnotationPlanner
    /// .fallbackMapSize`, which is the same size.
    private let mapSize = CGSize(width: 390, height: 660)

    /// A large virtual canvas used only by `wellSeparatedGrid` scenarios.
    /// `wellSeparatedGrid` needs BOTH a small enough total degree-extent to
    /// stay inside the region's cull margin (so `plan()`'s "cluster the
    /// WHOLE dataset" step, brewdesk#54's zero-churn design, never pulls in
    /// off-screen venues the test isn't reasoning about) AND a wide enough
    /// pixel spread per step to keep every footprint collision-free — a big
    /// canvas gets both at once without the step size itself having to grow.
    private let wideMapSize = CGSize(width: 2_400, height: 2_400)

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

    /// A grid spaced far enough apart, at `region()`'s default span and
    /// `mapSize`, that NO two footprints (pin, dot, or stack) can ever
    /// collide — every distinct cell differs from every other by at least
    /// one `step` in latitude or longitude, and a single step alone clears
    /// even the largest (stack) footprint on both axes. Tests that want to
    /// reason about exact counts use this instead of `grid(...)`, which
    /// packs venues close enough together to deliberately exercise
    /// collision handling.
    private func wellSeparatedGrid(count: Int, observed: Bool = true, scoreOffset: Int = 0) -> [Venue] {
        let columns = Int(Double(count).squareRoot().rounded(.up))
        let step = 0.0015
        let centerLat = 40.7359
        let centerLng = -73.9911
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
    /// `MapAnnotationPlanner.plan` used internally — reconstructed here
    /// (via the same `ScreenProjector`/`MarkerKind` the planner uses,
    /// visible through `@testable import`) so tests can assert "nothing
    /// overlaps" directly against what a viewer would actually see.
    private func footprints(for plan: MapAnnotationPlan, region: MKCoordinateRegion, mapSize: CGSize) -> [AABB] {
        let projector = ScreenProjector(region: region, size: mapSize)
        var boxes: [AABB] = []
        for pin in plan.pins {
            boxes.append(projector.footprint(.pin, at: CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)))
        }
        for dot in plan.dots {
            boxes.append(projector.footprint(.dot, at: CLLocationCoordinate2D(latitude: dot.lat, longitude: dot.lng)))
        }
        for cluster in plan.clusters {
            boxes.append(projector.footprint(.stack, at: cluster.coordinate))
        }
        return boxes
    }

    private func assertNoOverlaps(_ boxes: [AABB], sourceLocation: SourceLocation = #_sourceLocation) {
        guard boxes.count > 1 else { return }
        for i in 0..<(boxes.count - 1) {
            for j in (i + 1)..<boxes.count {
                #expect(!boxes[i].intersects(boxes[j]), "markers \(i) and \(j) overlap", sourceLocation: sourceLocation)
            }
        }
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

    // MARK: - bd#209: collision-free placement

    @Test func wellSeparatedVenuesAllRenderAsIndividualPinsAndDots() {
        // 25 well-separated observed venues: none collide, so all 25 win a
        // pin slot outright.
        let pins = wellSeparatedGrid(count: MapAnnotationPlanner.pinLimit)
        let plan = MapAnnotationPlanner.plan(venues: pins, region: region(), mapSize: wideMapSize)
        #expect(plan.pins.count == MapAnnotationPlanner.pinLimit)
        #expect(plan.dots.isEmpty)
        #expect(plan.clusters.isEmpty)
        assertNoOverlaps(footprints(for: plan, region: region(), mapSize: wideMapSize))
    }

    @Test func midDensityWellSeparatedFillsPinsThenDots() {
        let extraDots = 50
        let venues = wellSeparatedGrid(count: MapAnnotationPlanner.pinLimit + extraDots)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: region(), mapSize: wideMapSize)
        #expect(plan.pins.count == MapAnnotationPlanner.pinLimit)
        #expect(plan.dots.count == extraDots)
        #expect(plan.clusters.isEmpty)
        assertNoOverlaps(footprints(for: plan, region: region(), mapSize: wideMapSize))
    }

    @Test func overflowPastTheDotCandidateLimitClustersWithoutLosingVenues() {
        // 25 pins + 200 dot candidates + 50 genuine grid-cluster overflow —
        // note `pinLimit + dotCandidateLimit` (225) already exceeds
        // `maxAnnotations` (120) on its own, so this ALSO exercises the
        // global cap: not every dot candidate that's considered gets placed
        // (`dotCandidateLimit` is just the pool size collision/the cap then
        // trims), but the 50 venues that never even became dot candidates
        // must still show up, grouped into a stack — that's the actual
        // "overflow past the dot candidate limit" case this test names.
        let overflow = 50
        let count = MapAnnotationPlanner.pinLimit + MapAnnotationPlanner.dotCandidateLimit + overflow
        let venues = wellSeparatedGrid(count: count)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: region(), mapSize: wideMapSize)
        #expect(plan.pins.count == MapAnnotationPlanner.pinLimit)
        #expect(!plan.clusters.isEmpty, "overflow past the dot candidate limit must cluster")
        // `pinLimit + dotCandidateLimit` alone already exceeds
        // `maxAnnotations`, so the global cap ALSO trims some dot
        // candidates before they're ever attempted — those are a
        // deliberate drop (spec: "or dropped"), not a bug, so this checks
        // "never double-counted, never more than exists" rather than exact
        // conservation.
        let individuallyRendered = plan.pins.count + plan.dots.count
        let clusteredCount = plan.clusters.reduce(0) { $0 + $1.count }
        #expect(individuallyRendered + clusteredCount <= count)
        // But the 50 venues that never even competed for a pin or dot slot
        // (the genuine "overflow past the dot candidate limit" case this
        // test names) are never subject to that cap-driven drop — the
        // stacks phase runs before dots and isn't anywhere near the cap.
        #expect(clusteredCount >= overflow, "every venue that never became a dot candidate must still be represented")
        #expect(plan.annotationCount <= MapAnnotationPlanner.maxAnnotations)
        assertNoOverlaps(footprints(for: plan, region: region(), mapSize: wideMapSize))
    }

    @Test func denselyPackedPinCandidatesDemoteToDotsInsteadOfOverlapping() {
        // Two observed venues close enough that their PIN footprints
        // (44+8pt, half-width 26) overlap, but far enough apart that a DOT
        // footprint (12+8pt, half-width 10) does not — only one can win the
        // pin slot, but the loser must still render, demoted to a dot,
        // rather than either overlapping the winner or vanishing (bd#209's
        // whole point — #208 only ever separated pins from clusters, never
        // pin-vs-pin). ~0.0025° of latitude ≈ 47pt at this region/mapSize:
        // under the 52pt pin-pin threshold, over the 36pt pin-dot one.
        let a = venue(id: "a", lat: 40.7359, lng: -73.9911, score: 90)
        let b = venue(id: "b", lat: 40.7359 + 0.0025, lng: -73.9911, score: 88)
        let plan = MapAnnotationPlanner.plan(venues: [a, b], region: region(), mapSize: mapSize)
        #expect(plan.pins.count == 1, "only one of the two colliding candidates can be a pin")
        #expect(plan.pins.first?.id == "a", "the higher-scored candidate wins the pin slot")
        #expect(plan.dots.map(\.id) == ["b"], "the loser still renders, demoted to a dot")
        assertNoOverlaps(footprints(for: plan, region: region(), mapSize: mapSize))
    }

    @Test func selectedVenueAlwaysPlacedAndReservesItsFootprint() {
        let a = venue(id: "a", lat: 40.7359, lng: -73.9911, score: 50)
        // Deliberately near-identical coordinates and a HIGHER score than
        // the selected venue — without the bd#209 seeding pass this would
        // normally out-rank "a" for the pin slot.
        let b = venue(id: "b", lat: 40.735901, lng: -73.991101, score: 95)
        let plan = MapAnnotationPlanner.plan(venues: [a, b], region: region(), mapSize: mapSize, selectedVenueID: "a")
        #expect(plan.pins.contains { $0.id == "a" }, "the selected venue must always render as a pin")
        #expect(!plan.pins.contains { $0.id == "b" }, "nothing may overlap the selected venue's reserved footprint")
        assertNoOverlaps(footprints(for: plan, region: region(), mapSize: mapSize))
    }

    @Test func totalAnnotationsNeverExceedTheCapAtExtremeDensity() {
        let venues = grid(count: 2_000, extent: 0.02)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: region(), mapSize: mapSize)
        #expect(plan.annotationCount <= MapAnnotationPlanner.maxAnnotations)
        assertNoOverlaps(footprints(for: plan, region: region(), mapSize: mapSize))
    }

    @Test func stackPositionIsMemberCentroidNeverAGridCellCentre() throws {
        let testRegion = region()
        let cell = MapAnnotationPlanner.clusterCellDegrees(spanLongitude: testRegion.span.longitudeDelta)
        // 200 filler venues near the region centre soak up the entire dot
        // candidate budget, forcing the group below — far from the centre —
        // into the grid-clustering path instead of individual dots.
        let fillers = (0..<MapAnnotationPlanner.dotCandidateLimit).map { i -> Venue in
            venue(
                id: "filler\(i)",
                lat: 40.7359 + Double(i % 50) * 0.00002,
                lng: -73.9911 + Double(i / 50) * 0.00002,
                score: 40,
                observed: false
            )
        }
        // Five venues sharing one grid cell, skewed toward its edge — their
        // true average is nowhere near that cell's geometric centre. 0.01°
        // stays inside the map's actual PIXEL bounds at this region/mapSize
        // (span 0.035 ⇒ ±0.0175 is the strict on-screen half-extent; the
        // larger ±0.035 cull margin also accepts venues that never fit on
        // screen at all, which bd#210's edge-of-map bounds check on stack
        // nudging correctly refuses to place a marker at).
        let cornerLat = 40.7359 + 0.01
        let cornerLng = -73.9911 + 0.01
        let target = (0..<5).map { i in
            venue(id: "target\(i)", lat: cornerLat + Double(i) * 0.0002, lng: cornerLng + Double(i) * 0.0002, score: 40, observed: false)
        }
        let trueCentroidLat = target.map(\.lat).reduce(0, +) / Double(target.count)
        let trueCentroidLng = target.map(\.lng).reduce(0, +) / Double(target.count)
        let cellCentreLat = (cornerLat / cell).rounded(.down) * cell + cell / 2
        let cellCentreLng = (cornerLng / cell).rounded(.down) * cell + cell / 2

        let plan = MapAnnotationPlanner.plan(venues: fillers + target, region: testRegion, mapSize: mapSize)
        let stack = try #require(plan.clusters.first { $0.id.hasPrefix("cluster-") })

        #expect(abs(stack.latitude - trueCentroidLat) < 0.0005, "expected the true member centroid")
        #expect(abs(stack.longitude - trueCentroidLng) < 0.0005, "expected the true member centroid")
        let distanceFromCellCentre = hypot(stack.latitude - cellCentreLat, stack.longitude - cellCentreLng)
        #expect(distanceFromCellCentre > 0.0005, "must not sit at the raw grid cell centre (bd#209 — the #208 stack-over-the-river bug)")
    }

    @Test func aSingleStackIsNeverInternallyCappedAtNinetyNine() {
        // 300 venues tight enough that dot placement collides heavily,
        // funnelling most of them into one or two stacks — the MODEL must
        // carry the true count past 99 (the view layer is what decides how
        // to DISPLAY it — see `VenueClusterPill.displayCount`).
        let venues = grid(count: 300, extent: 0.002, observed: false)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: region(), mapSize: mapSize)
        #expect(plan.clusters.contains { $0.count > 99 }, "a dense group must not be silently capped below its real count")
        assertNoOverlaps(footprints(for: plan, region: region(), mapSize: mapSize))
    }

    // MARK: - bd#204: always-visible score pins

    @Test func unobservedVenuesNeverTakeAPinSlot() {
        // 300 unobserved venues plus 5 well-separated observed ones with
        // real scores: the 5 observed venues must be the pins, never a
        // fabricated-score unobserved venue (bd#159's rule extended to
        // bd#204's pin promotion).
        let unobserved = grid(count: 300, observed: false)
        let observed = (0..<5).map { i in
            venue(id: "obs\(i)", lat: 40.7359 + Double(i) * 0.004, lng: -73.9911, score: 90, observed: true)
        }
        let plan = MapAnnotationPlanner.plan(venues: unobserved + observed, region: region(), mapSize: mapSize)
        #expect(plan.pins.count == 5)
        #expect(Set(plan.pins.map(\.id)) == Set(observed.map(\.id)))
    }

    @Test func placedPinsAreAlwaysDrawnFromTheTopScoredObservedCandidates() {
        let venues = grid(count: 300)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: region(), mapSize: mapSize)

        let visible = MapAnnotationPlanner.culled(venues, region: region())
        let expectedCandidates = Set(
            visible
                .filter(\.isObserved)
                .sorted { $0.workScore != $1.workScore ? $0.workScore > $1.workScore : $0.id < $1.id }
                .prefix(MapAnnotationPlanner.pinLimit)
                .map(\.id)
        )
        #expect(
            Set(plan.pins.map(\.id)).isSubset(of: expectedCandidates),
            "no venue may win a pin slot that isn't among the top-ranked observed candidates"
        )
        // No pinned venue is also counted in a dot.
        let pinIDs = Set(plan.pins.map(\.id))
        #expect(plan.dots.allSatisfy { !pinIDs.contains($0.id) })
    }

    // MARK: - bd#210: chrome exclusion rects

    @Test func noPlacedPinOrStackIntersectsAnExclusionRect() {
        // A top-band exclusion (mimics the search header + status bar) and a
        // corner exclusion (mimics the locate button) — both large enough
        // that a dense 400-venue grid is guaranteed to have real candidates
        // land inside them.
        let testRegion = region()
        let exclusions = [
            CGRect(x: 0, y: 0, width: mapSize.width, height: 140),
            CGRect(x: mapSize.width - 80, y: mapSize.height - 140, width: 68, height: 68),
        ]
        let venues = grid(count: 400, extent: 0.03)
        let plan = MapAnnotationPlanner.plan(
            venues: venues, region: testRegion, mapSize: mapSize, exclusionRects: exclusions
        )

        let projector = ScreenProjector(region: testRegion, size: mapSize)
        let exclusionBoxes = exclusions.map { AABB(minX: $0.minX, maxX: $0.maxX, minY: $0.minY, maxY: $0.maxY) }
        for pin in plan.pins {
            let box = projector.footprint(.pin, at: CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng))
            for exclusion in exclusionBoxes {
                #expect(!box.intersects(exclusion), "pin \(pin.id) sits under an exclusion rect")
            }
        }
        for dot in plan.dots {
            let box = projector.footprint(.dot, at: CLLocationCoordinate2D(latitude: dot.lat, longitude: dot.lng))
            for exclusion in exclusionBoxes {
                #expect(!box.intersects(exclusion), "dot \(dot.id) sits under an exclusion rect")
            }
        }
        for cluster in plan.clusters {
            let box = projector.footprint(.stack, at: cluster.coordinate)
            for exclusion in exclusionBoxes {
                #expect(!box.intersects(exclusion), "stack \(cluster.id) sits under an exclusion rect")
            }
        }
        // Exclusion rects never break the base guarantee: still zero
        // marker-vs-marker overlaps.
        assertNoOverlaps(footprints(for: plan, region: testRegion, mapSize: mapSize))
    }

    @Test func pinUnderAnExclusionRectDemotesToADotWhenTheDotFootprintClears() {
        let testRegion = region()
        let projector = ScreenProjector(region: testRegion, size: mapSize)
        let target = venue(id: "under-chrome", lat: 40.7359, lng: -73.9911, score: 90)
        let point = projector.point(for: CLLocationCoordinate2D(latitude: target.lat, longitude: target.lng))
        // Stops 15pt short of the venue's own point on the X axis: inside
        // the pin's 26pt half-width (collides) but outside the dot's 10pt
        // half-width (clears).
        let exclusion = CGRect(x: point.x - 100, y: point.y - 50, width: 85, height: 100)
        let plan = MapAnnotationPlanner.plan(
            venues: [target], region: testRegion, mapSize: mapSize, exclusionRects: [exclusion]
        )
        #expect(plan.pins.isEmpty, "a pin under chrome must never render as a pin")
        #expect(plan.dots.map(\.id) == ["under-chrome"], "demotes to a dot once the smaller dot footprint clears the exclusion rect")
    }

    @Test func dotFullyInsideAnExclusionRectWithNothingNearbyIsSkipped() {
        let testRegion = region()
        let projector = ScreenProjector(region: testRegion, size: mapSize)
        // Unobserved (never a pin candidate) and alone — nothing nearby to
        // absorb it into a stack, so a collision here can only be dropped.
        let target = venue(id: "chrome-dot", lat: 40.7360, lng: -73.9912, score: 10, observed: false)
        let point = projector.point(for: CLLocationCoordinate2D(latitude: target.lat, longitude: target.lng))
        let exclusion = CGRect(x: point.x - 40, y: point.y - 40, width: 80, height: 80)
        let plan = MapAnnotationPlanner.plan(
            venues: [target], region: testRegion, mapSize: mapSize, exclusionRects: [exclusion]
        )
        #expect(plan.annotationCount == 0, "a lone venue fully under chrome, with nothing nearby to absorb it into, must not render")
    }

    @Test func planWithExclusionRectsStaysDeterministicAndWithinTheCap() {
        let testRegion = region()
        let exclusions = [
            CGRect(x: 0, y: 0, width: mapSize.width, height: 140),
            CGRect(x: mapSize.width - 80, y: mapSize.height - 140, width: 68, height: 68),
        ]
        let venues = grid(count: 400, extent: 0.03)
        let first = MapAnnotationPlanner.plan(
            venues: venues, region: testRegion, mapSize: mapSize, exclusionRects: exclusions
        )
        let second = MapAnnotationPlanner.plan(
            venues: venues, region: testRegion, mapSize: mapSize, exclusionRects: exclusions
        )
        #expect(first == second, "identical input (including exclusion rects) must plan identically")
        #expect(first.annotationCount <= MapAnnotationPlanner.maxAnnotations)
    }

    // MARK: - bd#209: determinism

    @Test func planIsDeterministicForTheSameInput() {
        let venues = grid(count: 400)
        let r = region()
        let first = MapAnnotationPlanner.plan(venues: venues, region: r, mapSize: mapSize)
        let second = MapAnnotationPlanner.plan(venues: venues, region: r, mapSize: mapSize)
        #expect(first == second)
    }

    // MARK: - bd#209: 500-random-venue property test (VERIFY step of the ticket)

    /// A tiny deterministic RNG — the planner itself must be reproducible
    /// for a FIXED input, but generating that fixed input across repeated
    /// `swift test` runs also needs to be reproducible, and
    /// `SystemRandomNumberGenerator` isn't.
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
        // A dense lower-Manhattan-scale bbox — small enough that, packed
        // with 500 venues, pin/dot/stack collisions are the norm, not the
        // exception, matching the evidence screenshot this ticket fixes.
        let venues = randomVenues(count: 500, seed: 42, centerLat: 40.7335, centerLng: -74.0027, extent: 0.02)
        let testRegion = region(lat: 40.7335, lng: -74.0027, span: 0.02)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize)

        // Zero intersecting footprints, anywhere in the rendered plan.
        assertNoOverlaps(footprints(for: plan, region: testRegion, mapSize: mapSize))

        // Total rendered annotations never exceed the cap.
        #expect(plan.annotationCount <= MapAnnotationPlanner.maxAnnotations)

        // Top-scored observed venues win pin slots — no pin is drawn from
        // outside the top-ranked observed candidates.
        let visible = MapAnnotationPlanner.culled(venues, region: testRegion)
        let expectedCandidates = Set(
            visible
                .filter(\.isObserved)
                .sorted { $0.workScore != $1.workScore ? $0.workScore > $1.workScore : $0.id < $1.id }
                .prefix(MapAnnotationPlanner.pinLimit)
                .map(\.id)
        )
        #expect(Set(plan.pins.map(\.id)).isSubset(of: expectedCandidates))

        // Every non-synthesized stack never drifts far from an actual
        // venue — the direct regression test for #208's stacks landing
        // outside the café area (over the Hudson).
        let cell = MapAnnotationPlanner.clusterCellDegrees(spanLongitude: testRegion.span.longitudeDelta)
        for cluster in plan.clusters {
            let nearestVenueDistance = venues.map { hypot($0.lat - cluster.latitude, $0.lng - cluster.longitude) }.min() ?? .infinity
            #expect(nearestVenueDistance <= cell * 1.5, "stack \(cluster.id) drifted away from every real venue")
        }

        // Deterministic: replanning the identical input yields an identical
        // plan.
        let replanned = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize)
        #expect(plan == replanned)
    }

    // MARK: - Clusters (grid mechanics, unaffected by bd#209's placement layer)

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
        // venue, never an empty list. Precise pixel collision math needs a
        // trustworthy region, so this rescue path skips it entirely
        // (bd#209) rather than laying out against a region it doesn't have.
        let venues = grid(count: 10)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: nil, mapSize: mapSize)
        #expect(Set(plan.pins.map(\.id)) == Set(venues.map(\.id)))
    }

    @Test func planFallsBackWithoutLosingVenuesWhenTheKnownRegionExcludesEveryVenue() {
        // A region that legitimately covers none of the venues (stale after
        // a search clear, a filter change, or a locate-button move with no
        // gesture to trigger a re-plan) must not render as zero pins while
        // venues exist — brewdesk#157's core symptom. Every venue must still
        // be represented SOMEWHERE (pin, dot, or folded into a stack) —
        // bd#209's collision pass still runs here (the region shape itself
        // is trustworthy, it just doesn't contain these venues), so this no
        // longer asserts an exact all-pins outcome the way the pre-bd#209
        // version did.
        let venues = grid(count: 10)
        let staleRegion = region(lat: 41.5, lng: -74.5, span: 0.01)
        #expect(MapAnnotationPlanner.culled(venues, region: staleRegion).isEmpty, "test setup: region must exclude every venue")

        let plan = MapAnnotationPlanner.plan(venues: venues, region: staleRegion, mapSize: mapSize)
        let individuallyRendered = Set(plan.pins.map(\.id)).union(plan.dots.map(\.id))
        let clusteredCount = plan.clusters.reduce(0) { $0 + $1.count }
        #expect(individuallyRendered.count + clusteredCount == venues.count, "no venue may silently vanish")
        assertNoOverlaps(footprints(for: plan, region: staleRegion, mapSize: mapSize))
    }

    @Test func planNeverFallsBackWhenTheRegionGenuinelyHasNoVenues() {
        // An empty `venues` input (e.g. a genuinely empty dataset) must stay
        // empty — the fallback only rescues a non-empty list a bad region
        // culled to nothing, never an honest zero.
        let plan = MapAnnotationPlanner.plan(venues: [], region: region(), mapSize: mapSize)
        #expect(plan.pins.isEmpty)
        #expect(plan.dots.isEmpty)
        #expect(plan.clusters.isEmpty)
    }

    // MARK: - Plan helpers

    @Test func planKnowsWhichVenuesItRendersIndividually() {
        let venues = grid(count: 10)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: region(), mapSize: mapSize)
        #expect(plan.containsVenue(id: venues[0].id))
        #expect(!plan.containsVenue(id: "absent"))

        let dense = wellSeparatedGrid(count: MapAnnotationPlanner.pinLimit + MapAnnotationPlanner.dotCandidateLimit + 50)
        let densePlan = MapAnnotationPlanner.plan(venues: dense, region: region(), mapSize: wideMapSize)
        #expect(!densePlan.containsVenue(id: "absent"), "clusters render no individual venue")
    }
}
