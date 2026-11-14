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

    private func venue(
        id: String, lat: Double, lng: Double, score: Int = 50, observed: Bool = true,
        scoreDisplay: ScoreDisplay = .notProvided
    ) -> Venue {
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
            distanceM: nil,
            scoreDisplay: scoreDisplay
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
    /// `MapAnnotationPlanner.plan` used internally — `.dot`s are
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
        // bd#241 (Bilal's round-3 selection, `size:"tiny"` — one step up
        // from "microplus"): every NUMBERED stop grows again; the 9.0→4
        // "no number" floor is unchanged.
        #expect(MapAnnotationPlanner.headDiameter(forMetersPerPoint: 20) == 4, "zoomed out clamps at the 4pt floor")
        #expect(MapAnnotationPlanner.headDiameter(forMetersPerPoint: 9.0) == 4)
        #expect(MapAnnotationPlanner.headDiameter(forMetersPerPoint: 5.4) == 14, "numbers (>= 11 pt) hold through a normal neighborhood view")
        #expect(MapAnnotationPlanner.headDiameter(forMetersPerPoint: 3.6) == 15)
        #expect(MapAnnotationPlanner.headDiameter(forMetersPerPoint: 1.8) == 20)
        #expect(MapAnnotationPlanner.headDiameter(forMetersPerPoint: 0.9) == 23)
        #expect(MapAnnotationPlanner.headDiameter(forMetersPerPoint: 0.1) == 23, "closer than the closest stop clamps at the 23pt ceiling")
        // Midpoint (on the LOG scale) between two stops lands strictly
        // between their diameters.
        let midMPP = (9.0 * 5.4).squareRoot()
        let mid = MapAnnotationPlanner.headDiameter(forMetersPerPoint: midMPP)
        #expect(mid > 4 && mid < 14)
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
        // 1.8 m/pt ⇒ 20pt heads (bd#241 "tiny" size), well above both the
        // shape and number thresholds; a generous step keeps every
        // footprint collision-free.
        let venues = wellSeparatedGrid(count: 30, step: 0.0015)
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: wideMapSize.width)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: wideMapSize)
        #expect(plan.markers.count == 30)
        #expect(plan.teardrops.count == 30)
        #expect(plan.dots.isEmpty)
        for marker in plan.teardrops {
            #expect(marker.showsNumber, "a 20pt un-demoted teardrop must show its number")
        }
        assertNoOverlaps(teardropFootprints(for: plan, region: testRegion, mapSize: wideMapSize))
    }

    @Test func denselyPackedCandidatesDemoteToDotsInsteadOfOverlapping() {
        // Two observed venues close enough that their TEARDROP footprints
        // (bd#241 "tiny" size: 20+1=21pt side, half 10.5) collide, but the
        // tight "head diameter + 1pt, tail excluded" box means only
        // genuinely overlapping heads ever demote.
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
        // 15pt head's footprint (bd#241 "tiny" size: 15+1=16pt side) needs
        // >16·3.6=57.6m of real-world clearance on at least one axis to stay
        // collision-free. 70m apart clears that with margin on both lat AND
        // lng (using the LONGITUDE metres-per-degree, the smaller of the two
        // at this latitude, so the same degree-step is >=70m on both axes).
        let lat = 40.7335
        let metersApart = 70.0
        let metersPerDegreeLng = 111_320.0 * cos(lat * .pi / 180)
        let stepDegrees = metersApart / metersPerDegreeLng
        let venues = wellSeparatedGrid(count: 20, step: stepDegrees, centerLat: lat, centerLng: -74.0027, observed: true)
        let testRegion = region(forMetersPerPoint: 3.6, mapWidth: mapSize.width, lat: lat, lng: -74.0027)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize)
        #expect(plan.teardrops.count == 20, "70m-separated venues at 3.6 m/pt (13.5pt heads) must not demote")
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

    // MARK: - bd#221: café-name labels ("names on")

    /// Every label's own screen-space box, reconstructed the same way
    /// `MapAnnotationPlanner.placeNameLabels` builds it internally, so a
    /// test can assert on the SAME geometry the planner collision-checked
    /// against rather than a hand-approximated one.
    private func labelBox(for placement: MarkerPlacement, region: MKCoordinateRegion, mapSize: CGSize, diameter: CGFloat) -> CGRect? {
        guard let side = placement.nameLabelSide else { return nil }
        let projector = ScreenProjector(region: region, size: mapSize)
        let point = projector.point(for: coordinate(of: placement.venue))
        let headCenter = CGPoint(x: point.x, y: point.y - diameter * MapAnnotationPlanner.headCenterFromTip)
        let width = min(MapAnnotationPlanner.labelMaxWidth, CGFloat(placement.venue.name.count) * MapAnnotationPlanner.labelCharWidth + MapAnnotationPlanner.labelPadding)
        let halfHeight = MapAnnotationPlanner.labelBoxHeight / 2
        let x = side == .trailing
            ? headCenter.x + diameter / 2 + MapAnnotationPlanner.labelGap
            : headCenter.x - diameter / 2 - MapAnnotationPlanner.labelGap - width
        return CGRect(x: x, y: headCenter.y - halfHeight, width: width, height: MapAnnotationPlanner.labelBoxHeight)
    }

    @Test func nameLabelsAppearOnlyOnNumberedTeardropsNeverOnDotsOrTheSelectedMarker() {
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: wideMapSize.width)
        let venues = wellSeparatedGrid(count: 10, step: 0.003)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: wideMapSize, selectedVenueID: venues[0].id)
        #expect(plan.markers.first { $0.id == venues[0].id }?.nameLabelSide == nil, "the selected marker must never carry a name label")
        #expect(plan.dots.allSatisfy { $0.nameLabelSide == nil })
        #expect(plan.unratedDots.allSatisfy { $0.nameLabelSide == nil })
        #expect(plan.teardrops.contains { $0.nameLabelSide != nil }, "at least one well-separated teardrop should win a label")
    }

    @Test func nameLabelsHiddenBelowTheNumberThreshold() {
        // 8 m/pt is well past the number threshold — every rated venue is a
        // dot, so no label may appear anywhere.
        let venues = grid(count: 30, extent: 0.02, observed: true)
        let testRegion = region(forMetersPerPoint: 8, mapWidth: mapSize.width)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize)
        #expect(plan.markers.allSatisfy { $0.nameLabelSide == nil })
    }

    @Test func nameLabelCountCapsAtEightNeighborhoodTwelveStreetBestScoredFirst() {
        let neighborhoodRegion = region(forMetersPerPoint: 3.6, mapWidth: wideMapSize.width)
        let venues = wellSeparatedGrid(count: 30, step: 0.002, scoreOffset: 0)
        let neighborhoodPlan = MapAnnotationPlanner.plan(venues: venues, region: neighborhoodRegion, mapSize: wideMapSize)
        let neighborhoodLabelCount = neighborhoodPlan.markers.filter { $0.nameLabelSide != nil }.count
        #expect(neighborhoodLabelCount <= MapAnnotationPlanner.labelCountNeighborhood)

        let streetRegion = region(forMetersPerPoint: 1.8, mapWidth: wideMapSize.width)
        let streetPlan = MapAnnotationPlanner.plan(venues: venues, region: streetRegion, mapSize: wideMapSize)
        let streetLabelCount = streetPlan.markers.filter { $0.nameLabelSide != nil }.count
        #expect(streetLabelCount <= MapAnnotationPlanner.labelCountStreet)

        // Best-scored first: the top-scored venue among the well-separated
        // set (plenty of room, no collisions) must always win a label slot.
        let best = venues.max { $0.workScore < $1.workScore }!
        #expect(streetPlan.markers.first { $0.id == best.id }?.nameLabelSide != nil, "the best-scored venue must win a label when there's room for one")
    }

    @Test func nameLabelsNeverOverlapAPinsTrueVisualHeadNotJustItsTipCenteredFootprint() {
        // Regression (bd#221 round 2 supervisor review, screenshot
        // evidence): `teardropFootprint`'s own collision box is centered
        // on a pin's TIP, which sits `diameter · headCenterFromTip` BELOW
        // its true circular head — a label that clears that footprint
        // alone can still visually run through the upper part of a
        // neighbour's actual head (a "52" pin drew straight through the
        // middle of "Joe Coffee Company"'s label in the live screenshot).
        // Dense enough that tight spacing between a labeled pin and its
        // neighbours is reliably exercised.
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: mapSize.width)
        let venues = grid(count: 80, extent: 0.012, observed: true)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize)
        let mpp = MapAnnotationPlanner.metersPerPoint(region: testRegion, mapWidth: mapSize.width)
        let diameter = MapAnnotationPlanner.headDiameter(forMetersPerPoint: mpp)
        let projector = ScreenProjector(region: testRegion, size: mapSize)

        func trueHeadRect(for placement: MarkerPlacement) -> CGRect {
            let point = projector.point(for: coordinate(of: placement.venue))
            let center = CGPoint(x: point.x, y: point.y - diameter * MapAnnotationPlanner.headCenterFromTip)
            let radius = diameter / 2
            return CGRect(x: center.x - radius, y: center.y - radius, width: diameter, height: diameter)
        }

        let labelBoxes = plan.markers.compactMap { labelBox(for: $0, region: testRegion, mapSize: mapSize, diameter: diameter) }
        let headRects = plan.teardrops.map(trueHeadRect(for:))

        for label in labelBoxes {
            for head in headRects {
                #expect(!label.intersects(head), "a name label overlaps a pin's true visual head circle, not just its tip-centered footprint")
            }
        }
    }

    @Test func nameLabelsNeverOverlapAnyPinFootprintOrAnotherLabel() {
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: mapSize.width)
        let venues = grid(count: 60, extent: 0.01, observed: true)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize)
        let mpp = MapAnnotationPlanner.metersPerPoint(region: testRegion, mapWidth: mapSize.width)
        let diameter = MapAnnotationPlanner.headDiameter(forMetersPerPoint: mpp)

        let labelBoxes = plan.markers.compactMap { labelBox(for: $0, region: testRegion, mapSize: mapSize, diameter: diameter) }
        let pinFootprints = teardropFootprints(for: plan, region: testRegion, mapSize: mapSize)

        for label in labelBoxes {
            for pin in pinFootprints {
                let pinRect = CGRect(x: pin.minX, y: pin.minY, width: pin.maxX - pin.minX, height: pin.maxY - pin.minY)
                #expect(!label.intersects(pinRect), "a name label overlaps a pin footprint")
            }
        }
        for i in 0..<max(labelBoxes.count - 1, 0) {
            for j in (i + 1)..<labelBoxes.count {
                #expect(!labelBoxes[i].intersects(labelBoxes[j]), "two name labels overlap")
            }
        }
    }

    @Test func nameLabelsNeverRenderPartlyOffScreen() {
        // A venue right at the map's own left edge: a trailing (right-side)
        // label has room, but a leading (left-side) one would run off the
        // visible map — must never be chosen, and every label actually
        // placed anywhere in this plan must fit within the map bounds.
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: mapSize.width)
        let projector = ScreenProjector(region: testRegion, size: mapSize)
        // Find a coordinate that projects near screen x=2 (well inside the
        // 6pt margin) so only a TRAILING label could ever fit.
        let edgeVenue = venue(id: "edge", lat: 40.7335, lng: -74.0027, score: 99)
        let edgePoint = projector.point(for: CLLocationCoordinate2D(latitude: edgeVenue.lat, longitude: edgeVenue.lng))
        // Shift the region so that point lands at x≈2.
        var shiftedRegion = testRegion
        shiftedRegion.center.longitude += (edgePoint.x - 2) / mapSize.width * testRegion.span.longitudeDelta
        let plan = MapAnnotationPlanner.plan(venues: [edgeVenue], region: shiftedRegion, mapSize: mapSize)
        let mpp = MapAnnotationPlanner.metersPerPoint(region: shiftedRegion, mapWidth: mapSize.width)
        let diameter = MapAnnotationPlanner.headDiameter(forMetersPerPoint: mpp)
        if let box = labelBox(for: plan.markers[0], region: shiftedRegion, mapSize: mapSize, diameter: diameter) {
            #expect(plan.markers[0].nameLabelSide == .trailing, "a pin hard against the left edge may only ever get a TRAILING label")
            #expect(box.minX >= 0, "a placed label must not render off the left edge of the map")
            #expect(box.maxX <= mapSize.width, "a placed label must not render off the right edge of the map")
        }
    }

    @Test func nameLabelsNeverOverlapAChromeExclusionRect() {
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: mapSize.width)
        let venues = grid(count: 60, extent: 0.01, observed: true)
        let exclusions = [CGRect(x: 0, y: 0, width: mapSize.width, height: 140)]
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize, exclusionRects: exclusions)
        let mpp = MapAnnotationPlanner.metersPerPoint(region: testRegion, mapWidth: mapSize.width)
        let diameter = MapAnnotationPlanner.headDiameter(forMetersPerPoint: mpp)
        let labelBoxes = plan.markers.compactMap { labelBox(for: $0, region: testRegion, mapSize: mapSize, diameter: diameter) }
        for label in labelBoxes {
            for exclusion in exclusions {
                #expect(!label.intersects(exclusion), "a name label sits under a chrome exclusion rect")
            }
        }
    }

    // MARK: - bd#227 (TestFlight build 29 screenshot regressions)

    /// Regression for "'Joe Coffee Company' and 'Starbucks' are drawn on
    /// top of each other": two independently-placed teardrops (neither
    /// demotes — their PIN footprints don't collide) spaced JUST above a
    /// numbered size's footprint threshold but under `labelBoxHeight`
    /// (14pt) plus the `labelCollisionMargin` (3pt) — a gap real enough
    /// that the OLD, unpadded `grid` check (bare AABB, no margin) would
    /// have called it "clear" while the two label boxes sat under a point
    /// apart, close enough to visually read as touching once real font
    /// ascenders and `HaloText`'s own 2pt-radius blur (applied twice) are
    /// drawn on top.
    ///
    /// bd#241: the smallest NUMBERED stop grew from 12.5pt to 14pt, whose
    /// own footprint (14+1=15pt) is no longer UNDER `labelBoxHeight`
    /// (14pt) — the original regression's exact stop doesn't reproduce the
    /// near-miss any more. A slightly-more-zoomed-out mpp (between the
    /// 9.0→4 and 5.4→14 stops) still interpolates to a smaller, still-
    /// numbered diameter whose footprint IS under `labelBoxHeight`, so the
    /// same scenario is reconstructed generically (derived from the live
    /// planner constants) instead of re-pinning a stale magic diameter.
    @Test func closelySpacedIndependentPinsGetVisiblyClearNonOverlappingLabels() {
        let testRegion = region(forMetersPerPoint: 6.0, mapWidth: mapSize.width, lat: 40.7335, lng: -74.0027)
        let mpp = MapAnnotationPlanner.metersPerPoint(region: testRegion, mapWidth: mapSize.width)
        let diameter = MapAnnotationPlanner.headDiameter(forMetersPerPoint: mpp)
        #expect(diameter >= MapAnnotationPlanner.numberThreshold, "test setup: must still be a numbered teardrop")
        let footprintSide = diameter + MapAnnotationPlanner.footprintPadding * 2
        #expect(
            footprintSide < MapAnnotationPlanner.labelBoxHeight,
            "test setup: footprint (\(footprintSide)) must be under labelBoxHeight (\(MapAnnotationPlanner.labelBoxHeight)) for this regression to reproduce"
        )
        // Screen separation just above the footprint threshold: clears it
        // (so BOTH venues win a real teardrop, matching the screenshot
        // showing two distinct numbered pins) but leaves only a hair of raw
        // AABB clearance between two `labelBoxHeight`-tall label boxes.
        let screenGap = footprintSide + 0.7
        let latPerPoint = testRegion.span.latitudeDelta / mapSize.height
        let latDelta = Double(screenGap) * latPerPoint
        let joeCoffeeCompany = venue(id: "joe-coffee-company", lat: 40.7335 + latDelta / 2, lng: -74.0027, score: 52)
        let starbucks = venue(id: "starbucks", lat: 40.7335 - latDelta / 2, lng: -74.0027, score: 52)
        let plan = MapAnnotationPlanner.plan(venues: [joeCoffeeCompany, starbucks], region: testRegion, mapSize: mapSize)
        #expect(plan.teardrops.count == 2, "test setup: both venues must win a teardrop slot, matching the screenshot")

        let labelBoxes = plan.markers.compactMap { labelBox(for: $0, region: testRegion, mapSize: mapSize, diameter: diameter) }
        #expect(labelBoxes.count == 2, "test setup: both venues must win a label, matching the screenshot")
        #expect(!labelBoxes[0].intersects(labelBoxes[1]), "two closely-spaced independent pins' name labels overlap")
        // Real, visible clearance — a HARDCODED minimum (independent of
        // whatever `labelCollisionMargin` happens to be set to), so this
        // test actually fails against the pre-fix 0.2pt near-miss gap
        // instead of trivially passing by referencing the same constant
        // being verified. If the two boxes ended up on the same side (same
        // x range), the gap between them must clear a real 2pt; if the fix
        // pushed one to the OTHER side of its own pin instead, their x
        // ranges won't overlap at all and this is trivially satisfied.
        let sameSide = labelBoxes[0].minX < labelBoxes[1].maxX && labelBoxes[1].minX < labelBoxes[0].maxX
        if sameSide {
            let gap = labelBoxes[0].minY < labelBoxes[1].minY
                ? labelBoxes[1].minY - labelBoxes[0].maxY
                : labelBoxes[0].minY - labelBoxes[1].maxY
            #expect(gap >= 2, "same-side labels only \(gap)pt apart — not visibly clear")
        }
    }

    /// Regression for "'Stumptown 76' is clipped at the right screen
    /// edge": a venue positioned so its trailing label's own right edge
    /// would have landed inside the OLD 6pt screen margin but outside the
    /// widened one — must now be OMITTED (or safely placed on the other
    /// side / within bounds), never rendered with any part of its box
    /// outside `[0, mapSize.width]`.
    @Test func nameLabelNearTheRightEdgeIsOmittedRatherThanClipped() {
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: mapSize.width)
        let projector = ScreenProjector(region: testRegion, size: mapSize)
        let mpp = MapAnnotationPlanner.metersPerPoint(region: testRegion, mapWidth: mapSize.width)
        let diameter = MapAnnotationPlanner.headDiameter(forMetersPerPoint: mpp)
        // `venue(id:...)`'s own name format is `"Venue \(id)"` — match it
        // exactly so the label-width estimate here is the same one
        // `placeNameLabels`/`labelBox` actually use, not a hand-picked
        // shorter stand-in that would silently change which side wins.
        let venueID = "stumptown"
        let venueName = "Venue \(venueID)"
        let labelWidth = min(MapAnnotationPlanner.labelMaxWidth, CGFloat(venueName.count) * MapAnnotationPlanner.labelCharWidth + MapAnnotationPlanner.labelPadding)
        // Place the venue so a TRAILING label's right edge would land
        // ~14pt inside the true device edge — outside the OLD 6pt margin
        // (would have been ACCEPTED, clipping-prone after any settle
        // drift) but inside a real, hardcoded 16pt safety zone this test
        // requires regardless of the exact tunable constant's value.
        let requiredSafeZone: CGFloat = 16
        let targetTrailingMaxX = mapSize.width - 14
        let targetHeadCenterX = targetTrailingMaxX - MapAnnotationPlanner.labelGap - labelWidth - diameter / 2
        let lngPerPoint = testRegion.span.longitudeDelta / mapSize.width
        let currentPoint = projector.point(for: CLLocationCoordinate2D(latitude: 40.7335, longitude: -74.0027))
        let lngShift = Double(targetHeadCenterX - currentPoint.x) * lngPerPoint
        let stumptown = venue(id: venueID, lat: 40.7335, lng: -74.0027 + lngShift, score: 76, scoreDisplay: .rated(76))

        let plan = MapAnnotationPlanner.plan(venues: [stumptown], region: testRegion, mapSize: mapSize)
        // Unconditional: a trailing label whose right edge would land only
        // 14pt from the screen edge must never actually be CHOSEN — the
        // pre-fix 6pt margin accepted exactly this (clipping-prone after
        // settle drift). The planner may still legitimately fall back to
        // a leading label (there's nothing else nearby to block it) or
        // omit entirely; either is fine, only an unsafe trailing choice
        // isn't.
        #expect(plan.markers[0].nameLabelSide != .trailing, "a trailing label only 14pt from the screen edge must not be chosen — it renders clipping-prone")
        if let box = labelBox(for: plan.markers[0], region: testRegion, mapSize: mapSize, diameter: diameter) {
            #expect(box.minX >= 0 && box.maxX <= mapSize.width, "a placed label must render fully inside the map bounds")
            #expect(box.maxX <= mapSize.width - requiredSafeZone, "a placed label must clear a real screen-edge safety zone")
        }
        // Either way, the PIN itself (with its own number) must still
        // render — only the LABEL may be omitted near an edge.
        #expect(plan.teardrops.count == 1, "the pin itself must still render even when its label is omitted near an edge")
    }

    /// Regression for "'Caffe Reggio' runs into the '82' pin" (light
    /// mode): a lower-scored, well-separated venue (eligible for a label)
    /// sitting close enough to a HIGHER-scored neighbour's pin that a
    /// naive label placement would visually run through that neighbour's
    /// true circular head — named after the specific screenshot pair for
    /// traceability; the underlying invariant is the same one
    /// `nameLabelsNeverOverlapAPinsTrueVisualHeadNotJustItsTipCenteredFootprint`
    /// covers generically.
    @Test func namedRegressionCaffeReggioLabelNeverOverlapsTheEightyTwoPinsHead() {
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: mapSize.width, lat: 40.7335, lng: -74.0027)
        let mpp = MapAnnotationPlanner.metersPerPoint(region: testRegion, mapWidth: mapSize.width)
        let diameter = MapAnnotationPlanner.headDiameter(forMetersPerPoint: mpp)
        let projector = ScreenProjector(region: testRegion, size: mapSize)
        // "82" sits just above-right of where "Caffe Reggio"'s trailing
        // label would naturally land — close enough that only the TRUE
        // head-circle check (not the tip-centered footprint alone) can
        // catch it.
        let eightyTwo = venue(id: "eighty-two", lat: 40.7335, lng: -74.0027, score: 82)
        let point = projector.point(for: CLLocationCoordinate2D(latitude: 40.7335, longitude: -74.0027))
        let neighborScreenOffset = CGPoint(x: diameter / 2 + MapAnnotationPlanner.labelGap + 20, y: -diameter * 0.6)
        let latPerPoint = testRegion.span.latitudeDelta / mapSize.height
        let lngPerPoint = testRegion.span.longitudeDelta / mapSize.width
        let caffeReggio = venue(
            id: "caffe-reggio",
            lat: 40.7335 - Double(neighborScreenOffset.y) * latPerPoint,
            lng: -74.0027 + Double(neighborScreenOffset.x) * lngPerPoint,
            score: 69
        )
        _ = point
        let plan = MapAnnotationPlanner.plan(venues: [eightyTwo, caffeReggio], region: testRegion, mapSize: mapSize)

        func trueHeadRect(for placement: MarkerPlacement) -> CGRect {
            let p = projector.point(for: coordinate(of: placement.venue))
            let center = CGPoint(x: p.x, y: p.y - diameter * MapAnnotationPlanner.headCenterFromTip)
            let radius = diameter / 2
            return CGRect(x: center.x - radius, y: center.y - radius, width: diameter, height: diameter)
        }
        let headRects = plan.teardrops.map(trueHeadRect(for:))
        let labelBoxes = plan.markers.compactMap { labelBox(for: $0, region: testRegion, mapSize: mapSize, diameter: diameter) }
        for label in labelBoxes {
            for head in headRects {
                #expect(!label.intersects(head), "a name label overlaps a neighbouring pin's true visual head")
            }
        }
    }

    @Test func nameLabelsNeverChangeAPinsOwnKindOrNumberEvenInADenseLabelHostileLayout() {
        // Dense enough that most candidates LOSE every label placement
        // attempt — labels are pure decoration computed strictly after
        // every pin already exists, so even here every teardrop's
        // `showsNumber` must still be exactly "diameter >= numberThreshold"
        // and every dot must still show no number, independent of whether
        // it also picked up a label.
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: mapSize.width)
        let venues = grid(count: 150, extent: 0.006, observed: true)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize)
        let mpp = MapAnnotationPlanner.metersPerPoint(region: testRegion, mapWidth: mapSize.width)
        let diameter = MapAnnotationPlanner.headDiameter(forMetersPerPoint: mpp)
        let expectedShowsNumber = diameter >= MapAnnotationPlanner.numberThreshold
        for marker in plan.teardrops {
            #expect(marker.showsNumber == expectedShowsNumber, "a name label must never change whether its own pin shows a number")
        }
        #expect(plan.dots.allSatisfy { !$0.showsNumber })
        // Plenty of candidates in a 0.006°-extent, 150-venue grid at 1.8
        // m/pt must lose the label race entirely — confirms this test is
        // actually exercising the "no room" path, not a vacuous one.
        #expect(plan.markers.contains { $0.showsNumber && $0.nameLabelSide == nil }, "test setup: expected at least one numbered pin to lose every label attempt")
    }

    // MARK: - bd#265: unrated venues are small neutral cup pins, then dots

    /// True on-screen head rect (head center ± radius) for every teardrop in
    /// the plan, rated and unrated alike — the mixed-size overlap check.
    private func headRects(for plan: MapAnnotationPlan, region: MKCoordinateRegion, mapSize: CGSize) -> [AABB] {
        let projector = ScreenProjector(region: region, size: mapSize)
        return plan.teardrops.compactMap { placement in
            guard let diameter = placement.kind.teardropDiameter else { return nil }
            let tip = projector.point(for: coordinate(of: placement.venue))
            let centerY = tip.y - diameter * MapAnnotationPlanner.headCenterFromTip
            return AABB(minX: tip.x - diameter / 2, maxX: tip.x + diameter / 2, minY: centerY - diameter / 2, maxY: centerY + diameter / 2)
        }
    }

    @Test func unratedVenuesNeverShowANumberOrCompeteWithRatedPlacement() {
        let unrated = grid(count: 200, extent: 0.02, observed: false)
        let rated = wellSeparatedGrid(count: 5, step: 0.003, observed: true, scoreOffset: 90)
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: wideMapSize.width)
        let ratedOnly = MapAnnotationPlanner.plan(venues: rated, region: testRegion, mapSize: wideMapSize)
        let plan = MapAnnotationPlanner.plan(venues: unrated + rated, region: testRegion, mapSize: wideMapSize)
        let ratedIDs = Set(rated.map(\.id))
        #expect((plan.unratedPins + plan.unratedDots).allSatisfy { !ratedIDs.contains($0.id) && !$0.showsNumber })
        // Rated first: adding 200 unrated venues changes nothing about how
        // any rated venue is drawn, and they stay at the front of the plan.
        #expect(Array(plan.markers.prefix(ratedOnly.markers.count)) == ratedOnly.markers)
        for marker in plan.markers where ratedIDs.contains(marker.id) {
            #expect(marker.showsNumber && !marker.isUnrated, "a well-separated rated venue at 1.8 m/pt must show its number")
        }
    }

    @Test func ratedPinsAlwaysWinPlacementOverACollidingUnratedVenue() {
        // An unrated venue sitting exactly on a rated one, and dead centre.
        let rated = venue(id: "rated", lat: 40.7335, lng: -74.0027, score: 80)
        let unrated = venue(id: "unrated", lat: 40.7335, lng: -74.0027, observed: false)
        let testRegion = region(forMetersPerPoint: 3.6, mapWidth: mapSize.width)
        let plan = MapAnnotationPlanner.plan(venues: [unrated, rated], region: testRegion, mapSize: mapSize)
        #expect(plan.teardrops.map(\.id) == ["rated"])
        #expect(plan.unratedDots.map(\.id) == ["unrated"])
    }

    @Test func unratedPinIsOneStepSmallerThanTheRatedPinAtEveryPinZoom() throws {
        for mpp in [5.4, 3.6, 1.8, 0.9] {
            let rated = MapAnnotationPlanner.headDiameter(forMetersPerPoint: mpp)
            let unrated = try #require(MapAnnotationPlanner.unratedPinDiameter(forMetersPerPoint: mpp))
            #expect(unrated < rated && unrated >= MapAnnotationPlanner.unratedPinMinDiameter)
        }
        #expect(MapAnnotationPlanner.unratedPinDiameter(forMetersPerPoint: 9) == nil)
    }

    @Test func wellSeparatedUnratedVenuesBecomeTappablePinsInAnAreaWithNoRatedVenues() {
        let unrated = wellSeparatedGrid(count: 30, step: 0.002, centerLat: 40.7736, centerLng: -73.9566, observed: false)
        let testRegion = region(forMetersPerPoint: 3.6, mapWidth: wideMapSize.width, lat: 40.7736, lng: -73.9566)
        let plan = MapAnnotationPlanner.plan(venues: unrated, region: testRegion, mapSize: wideMapSize)
        #expect(plan.unratedPins.count == 30)
        #expect(plan.teardrops.allSatisfy { $0.isUnrated && !$0.showsNumber })
        #expect(plan.unratedDots.isEmpty)
    }

    @Test func unratedPinsCapAtSixtyNearestTheCentreAndTheRestAreDots() {
        // 144 unrated venues, 40pt apart at this zoom — every one of them
        // COULD be a pin, so only the cap stops them.
        let centerLat = 40.7736, centerLng = -73.9566
        let unrated = wellSeparatedGrid(count: 144, step: 0.0013, centerLat: centerLat, centerLng: centerLng, observed: false)
        let testRegion = region(forMetersPerPoint: 3.6, mapWidth: wideMapSize.width, lat: centerLat, lng: centerLng)
        let plan = MapAnnotationPlanner.plan(venues: unrated, region: testRegion, mapSize: wideMapSize)

        #expect(plan.unratedPins.count == MapAnnotationPlanner.maxUnratedPins)
        #expect(plan.unratedDots.count == 144 - MapAnnotationPlanner.maxUnratedPins, "venues beyond the cap stay visible as dots")
        #expect(plan.unratedDots.allSatisfy { $0.kind == .dot && $0.isUnrated })

        func distanceSquared(_ placement: MarkerPlacement) -> Double {
            let dLat = placement.venue.lat - centerLat, dLng = placement.venue.lng - centerLng
            return dLat * dLat + dLng * dLng
        }
        let farthestPin = plan.unratedPins.map(distanceSquared).max() ?? 0
        let nearestDot = plan.unratedDots.map(distanceSquared).min() ?? .infinity
        #expect(farthestPin <= nearestDot, "the pins must be the venues nearest the viewport centre")
    }

    @Test func denseUnratedVenuesNeverOverlapEachOtherOrARatedPin() {
        let unrated = randomVenues(count: 282, seed: 7, centerLat: 40.7736, centerLng: -73.9566, extent: 0.02, observed: false)
        let rated = [
            venue(id: "ra", lat: 40.7740, lng: -73.9570, score: 82),
            venue(id: "rb", lat: 40.7730, lng: -73.9555, score: 71),
            venue(id: "rc", lat: 40.7752, lng: -73.9580, score: 64),
        ]
        for mpp in [5.4, 3.6, 1.8] {
            let testRegion = region(forMetersPerPoint: mpp, mapWidth: mapSize.width, lat: 40.7736, lng: -73.9566)
            let plan = MapAnnotationPlanner.plan(
                venues: unrated + rated, region: testRegion, mapSize: mapSize, selectedVenueID: "rb"
            )
            #expect(!plan.unratedPins.isEmpty, "a dense unrated neighbourhood must show pins at \(mpp) m/pt")
            #expect(plan.unratedPins.count <= MapAnnotationPlanner.maxUnratedPins)
            #expect(plan.annotationCount <= MapAnnotationPlanner.maxAnnotations)
            assertNoOverlaps(teardropFootprints(for: plan, region: testRegion, mapSize: mapSize))
            assertNoOverlaps(headRects(for: plan, region: testRegion, mapSize: mapSize))
            #expect(plan.markers.map(\.id).count == Set(plan.markers.map(\.id)).count)
        }
    }

    @Test func unratedPinUnderChromeIsSkippedNotLeftAsADot() {
        let unrated = venue(id: "u", lat: 40.7335, lng: -74.0027, observed: false)
        let testRegion = region(forMetersPerPoint: 3.6, mapWidth: mapSize.width)
        let chrome = CGRect(x: 0, y: mapSize.height / 2 - 40, width: mapSize.width, height: 80)
        let plan = MapAnnotationPlanner.plan(venues: [unrated], region: testRegion, mapSize: mapSize, exclusionRects: [chrome])
        #expect(plan.markers.isEmpty)
    }

    @Test func unratedVenuesAreDotsOnlyBeyondThePinZoomAndGoneAfterTheFade() {
        let unrated = grid(count: 50, extent: 0.02, observed: false)
        // 8 m/pt used to draw nothing at all (the old 5 m/pt cut).
        let wide = MapAnnotationPlanner.plan(
            venues: unrated, region: region(forMetersPerPoint: 8, mapWidth: mapSize.width, lat: 40.7359, lng: -73.9911), mapSize: mapSize
        )
        #expect(wide.unratedDots.count == 50)
        #expect(wide.teardrops.isEmpty)
        let faded = MapAnnotationPlanner.plan(
            venues: unrated, region: region(forMetersPerPoint: 17, mapWidth: mapSize.width, lat: 40.7359, lng: -73.9911), mapSize: mapSize
        )
        #expect(faded.markers.isEmpty)
    }

    @Test func unratedDotOpacityIsFullToTwelveMetresPerPointThenFadesOut() {
        #expect(MapAnnotationPlanner.unratedDotOpacity(forMetersPerPoint: 3.6) == 1)
        #expect(MapAnnotationPlanner.unratedDotOpacity(forMetersPerPoint: 12) == 1)
        let mid = MapAnnotationPlanner.unratedDotOpacity(forMetersPerPoint: 14)
        #expect(mid > 0.4 && mid < 0.6)
        #expect(MapAnnotationPlanner.unratedDotOpacity(forMetersPerPoint: 16) == 0)
        #expect(MapAnnotationPlanner.unratedDotOpacity(forMetersPerPoint: 40) == 0)
    }

    @Test func unratedPinsCarryUpToSixNamesOnlyWhenFewerThanFiveRatedVenuesAreInView() {
        let centerLat = 40.7736, centerLng = -73.9566
        let unrated = wellSeparatedGrid(count: 36, step: 0.006, centerLat: centerLat, centerLng: centerLng, observed: false)
        let testRegion = region(forMetersPerPoint: 3.6, mapWidth: wideMapSize.width, lat: centerLat, lng: centerLng)
        func ratedVenues(_ count: Int) -> [Venue] {
            (0..<count).map { venue(id: "r\($0)", lat: centerLat + 0.0031 + Double($0) * 0.006, lng: centerLng + 0.0031, score: 80) }
        }

        let sparse = MapAnnotationPlanner.plan(venues: unrated + ratedVenues(4), region: testRegion, mapSize: wideMapSize)
        let labelled = sparse.unratedPins.filter { $0.nameLabelSide != nil }
        #expect(labelled.count == MapAnnotationPlanner.unratedLabelCount, "4 rated venues in view: six unrated pins get names")
        // …and they are the six nearest the centre that had room.
        #expect(Set(labelled.map(\.id)).isSubset(of: Set(sparse.unratedPins.prefix(12).map(\.id))))

        let enough = MapAnnotationPlanner.plan(venues: unrated + ratedVenues(5), region: testRegion, mapSize: wideMapSize)
        #expect(enough.unratedPins.count == 36)
        #expect(enough.unratedPins.allSatisfy { $0.nameLabelSide == nil }, "5 rated venues in view: unrated pins stay unnamed")
    }

    @Test func ratedVenuesOutsideTheViewportDoNotSuppressUnratedNames() {
        let centerLat = 40.7736, centerLng = -73.9566
        let unrated = wellSeparatedGrid(count: 9, step: 0.006, centerLat: centerLat, centerLng: centerLng, observed: false)
        let testRegion = region(forMetersPerPoint: 3.6, mapWidth: mapSize.width, lat: centerLat, lng: centerLng)
        // Inside the cull margin (still planned) but off screen.
        let offscreen = (0..<8).map {
            venue(id: "off\($0)", lat: centerLat + testRegion.span.latitudeDelta * 0.8, lng: centerLng + Double($0) * 0.0004, score: 80)
        }
        let plan = MapAnnotationPlanner.plan(venues: unrated + offscreen, region: testRegion, mapSize: mapSize)
        #expect(plan.unratedPins.contains { $0.nameLabelSide != nil })
    }

    @Test func unratedNameLabelsNeverOverlapAnyPinOrEachOther() {
        let unrated = randomVenues(count: 120, seed: 11, centerLat: 40.7736, centerLng: -73.9566, extent: 0.012, observed: false)
        let testRegion = region(forMetersPerPoint: 3.6, mapWidth: mapSize.width, lat: 40.7736, lng: -73.9566)
        let plan = MapAnnotationPlanner.plan(venues: unrated, region: testRegion, mapSize: mapSize)
        let diameter = MapAnnotationPlanner.unratedPinDiameter(forMetersPerPoint: 3.6) ?? 0
        let labels = plan.unratedPins.compactMap { labelBox(for: $0, region: testRegion, mapSize: mapSize, diameter: diameter) }
        #expect(!labels.isEmpty && labels.count <= MapAnnotationPlanner.unratedLabelCount)
        let heads = headRects(for: plan, region: testRegion, mapSize: mapSize)
        for (i, label) in labels.enumerated() {
            let box = AABB(minX: label.minX, maxX: label.maxX, minY: label.minY, maxY: label.maxY)
            #expect(!heads.contains { $0.intersects(box) }, "label \(i) runs through a pin head")
            for other in labels.dropFirst(i + 1) {
                #expect(!label.intersects(other), "two unrated labels overlap")
            }
        }
    }

    @Test func selectedUnratedVenueIsAFullSizeNeutralPin() throws {
        let unrated = venue(id: "u", lat: 40.7335, lng: -74.0027, observed: false)
        let testRegion = region(forMetersPerPoint: 3.6, mapWidth: mapSize.width)
        let plan = MapAnnotationPlanner.plan(venues: [unrated], region: testRegion, mapSize: mapSize, selectedVenueID: "u")
        let marker = try #require(plan.markers.first)
        #expect(marker.kind == .teardrop(diameter: MapAnnotationPlanner.selectedDiameter))
        #expect(marker.isSelected && marker.isUnrated && !marker.showsNumber)
    }

    @Test func ratedBudgetIsSpentBeforeUnratedVenues() {
        // Rated venues alone exceed the cap; no unrated venue should ever
        // squeeze in ahead of a rated marker.
        let rated = grid(count: MapAnnotationPlanner.maxAnnotations + 50, extent: 0.02, observed: true)
        let unrated = grid(count: 30, centerLat: 40.74, centerLng: -73.98, extent: 0.005, observed: false)
        let testRegion = region(forMetersPerPoint: 3.6, mapWidth: mapSize.width)
        let plan = MapAnnotationPlanner.plan(venues: rated + unrated, region: testRegion, mapSize: mapSize)
        #expect(plan.annotationCount <= MapAnnotationPlanner.maxAnnotations)
        #expect(plan.markers.allSatisfy { $0.venue.isObserved }, "no unrated venue should have taken a slot from a rated venue")
    }

    // MARK: - brewdesk#222: forced-unrated input classification (honest filters)

    /// The WeWork shape (TestFlight build 28): a genuinely RATED venue
    /// (`observed: true`, a real score) whose id is in `forcedUnratedVenueIDs`
    /// must draw as a neutral dot, not a teardrop/tier dot/cup pin — `CafeMapScreen` passes the
    /// active filter's `unknownVenues` ids here.
    @Test func forcedUnratedVenueDrawsAsANeutralDotDespiteBeingActuallyRated() {
        let weWork = venue(id: "wework", lat: 40.7360, lng: -73.9908, score: 48, observed: true)
        let cafe = venue(id: "cafe", lat: 40.7300, lng: -73.9800, score: 70, observed: true)
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: wideMapSize.width)

        let plan = MapAnnotationPlanner.plan(
            venues: [weWork, cafe], region: testRegion, mapSize: wideMapSize,
            forcedUnratedVenueIDs: ["wework"]
        )

        #expect(plan.unratedDots.map(\.id) == ["wework"])
        #expect(plan.teardrops.map(\.id) + plan.dots.map(\.id) == ["cafe"])
    }

    /// An empty `forcedUnratedVenueIDs` (the default, and what a model with
    /// no active filter always passes) never changes the plan — behaviour
    /// unchanged while no filter is active.
    @Test func emptyForcedUnratedVenueIDsIsANoOp() {
        let rated = wellSeparatedGrid(count: 8, step: 0.003, observed: true)
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: wideMapSize.width)

        let withoutOverride = MapAnnotationPlanner.plan(venues: rated, region: testRegion, mapSize: wideMapSize)
        let withEmptyOverride = MapAnnotationPlanner.plan(
            venues: rated, region: testRegion, mapSize: wideMapSize, forcedUnratedVenueIDs: []
        )

        #expect(withoutOverride == withEmptyOverride)
    }

    /// A genuinely unrated venue named in `forcedUnratedVenueIDs` is a
    /// neutral dot, not even a cup pin (bd#265) — the override only ever
    /// DEMOTES, never promotes.
    @Test func forcedUnratedVenueIDsNeverPromotesAGenuinelyUnratedVenue() {
        let unrated = venue(id: "unrated", lat: 40.7360, lng: -73.9908, observed: false)
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: wideMapSize.width)

        let plan = MapAnnotationPlanner.plan(
            venues: [unrated], region: testRegion, mapSize: wideMapSize,
            forcedUnratedVenueIDs: ["unrated"]
        )

        #expect(plan.unratedDots.map(\.id) == ["unrated"])
        #expect(plan.teardrops.isEmpty)
    }

    // MARK: - brewdesk#213: planner keys off `isRated`, not `isObserved` directly

    /// The server's explicit `scoreDisplay` must override the client-side
    /// `isObserved` heuristic in BOTH directions: a venue whose claims look
    /// "observed" but the server says `scoreDisplay: null` must draw unrated, and a
    /// venue whose claims look estimate-only but the server sends a real
    /// number must still get a numbered teardrop.
    @Test func plannerHonorsExplicitScoreDisplayOverTheObservedHeuristic() throws {
        let serverSaysUnrated = venue(
            id: "server-null", lat: 40.7359, lng: -73.9911, score: 40,
            observed: true, scoreDisplay: .notRated
        )
        let serverSaysRated = venue(
            id: "server-rated", lat: 40.7370, lng: -73.9900, score: 77,
            observed: false, scoreDisplay: .rated(77)
        )
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: mapSize.width, lat: 40.7359, lng: -73.9911)
        let plan = MapAnnotationPlanner.plan(
            venues: [serverSaysUnrated, serverSaysRated], region: testRegion, mapSize: mapSize
        )

        let unratedMarker = try #require(plan.markers.first { $0.id == "server-null" })
        #expect(unratedMarker.isUnrated && !unratedMarker.showsNumber,
                "isObserved-true venue with an explicit scoreDisplay:null must draw unrated, not as a numbered teardrop")
        #expect(!plan.dots.contains { $0.id == "server-null" })

        let ratedMarker = try #require(plan.markers.first { $0.id == "server-rated" })
        #expect(!ratedMarker.isUnrated,
                "isObserved-false venue with an explicit scoreDisplay:rated must never draw unrated")
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

    /// bd#217 (TestFlight build 26 regression): a `.dot` renders at the
    /// SAME coordinate its would-be teardrop attempt used, and `.dot`s are
    /// never themselves exclusion-checked (they're a native `MapCircle`,
    /// drawn independently) — so falling back to a dot here, as the bd#210/
    /// #212 behavior this replaces used to, still put a marker right under
    /// the chrome, just a smaller one. That was the exact bug: a small
    /// green dot peeking out from under the "Search this area" pill.
    /// A candidate that only collides with CHROME must now be skipped
    /// outright; see `denselyPackedCandidatesDemoteToDotsInsteadOfOverlapping`
    /// above for a SIBLING-teardrop collision, which still demotes to a dot.
    @Test func teardropUnderAnExclusionRectIsSkippedNotDemotedToAVisibleDot() {
        let testRegion = region(forMetersPerPoint: 1.8, mapWidth: mapSize.width)
        let projector = ScreenProjector(region: testRegion, size: mapSize)
        let target = venue(id: "under-chrome", lat: 40.7335, lng: -74.0027, score: 90)
        let point = projector.point(for: CLLocationCoordinate2D(latitude: target.lat, longitude: target.lng))
        let exclusion = CGRect(x: point.x - 20, y: point.y - 20, width: 40, height: 40)
        let plan = MapAnnotationPlanner.plan(venues: [target], region: testRegion, mapSize: mapSize, exclusionRects: [exclusion])
        #expect(plan.markers.isEmpty, "a venue that only collides with CHROME must be skipped entirely, never fall back to a dot under the same chrome")
    }

    /// Companion to the skip test above: every DOT actually placed in a
    /// dense, chrome-covered plan must have a coordinate that's genuinely
    /// clear of every exclusion rect — not just every TEARDROP (already
    /// covered by `noPlacedTeardropIntersectsAnExclusionRect`).
    @Test func noPlacedDotSitsUnderAnExclusionRectEither() {
        let testRegion = region(forMetersPerPoint: 3.6, mapWidth: mapSize.width)
        let exclusions = [
            CGRect(x: 0, y: 0, width: mapSize.width, height: 140),
            CGRect(x: mapSize.width - 80, y: mapSize.height - 140, width: 68, height: 68),
        ]
        let venues = grid(count: 400, extent: 0.03)
        let plan = MapAnnotationPlanner.plan(venues: venues, region: testRegion, mapSize: mapSize, exclusionRects: exclusions)
        let exclusionBoxes = exclusions.map { AABB(minX: $0.minX, maxX: $0.maxX, minY: $0.minY, maxY: $0.maxY) }
        let projector = ScreenProjector(region: testRegion, size: mapSize)
        let mpp = MapAnnotationPlanner.metersPerPoint(region: testRegion, mapWidth: mapSize.width)
        let dotDiameter = MapAnnotationPlanner.headDiameter(forMetersPerPoint: mpp)
        for dot in plan.dots {
            let point = projector.point(for: coordinate(of: dot.venue))
            let box = MapAnnotationPlanner.teardropFootprint(diameter: dotDiameter, at: point)
            for exclusion in exclusionBoxes {
                #expect(!box.intersects(exclusion), "demoted dot \(dot.id)'s own coordinate sits under an exclusion rect")
            }
        }
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

    private func randomVenues(
        count: Int, seed: UInt64, centerLat: Double, centerLng: Double, extent: Double, observed forcedObserved: Bool? = nil
    ) -> [Venue] {
        var rng = SeededGenerator(seed: seed)
        return (0..<count).map { index in
            let dLat = Double.random(in: -extent / 2...extent / 2, using: &rng)
            let dLng = Double.random(in: -extent / 2...extent / 2, using: &rng)
            let score = Int.random(in: 0...100, using: &rng)
            let observed = forcedObserved ?? (Double.random(in: 0...1, using: &rng) < 0.7)
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

        // Neutral (unrated) drawing is used for exactly the unobserved
        // venues, and only a rated venue ever shows a number.
        for marker in plan.markers {
            #expect(marker.isUnrated == !marker.venue.isObserved)
            #expect(!marker.showsNumber || marker.venue.isObserved)
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
        // bd#265: a 20% zoom drift is enough to overlap densely planned
        // pins, so it re-plans; a 5% wobble does not.
        #expect(CafeMapScreen.needsReplan(from: current, to: region(span: 0.035 * 1.2)))
        #expect(CafeMapScreen.needsReplan(from: current, to: region(span: 0.035 * 0.8)))
        #expect(!CafeMapScreen.needsReplan(from: current, to: region(span: 0.035 * 1.05)))
    }

    // MARK: - bd#265: the plan projects onto the whole map plane

    /// The measured iPhone 17 layout: a 402×374.67 map window sitting
    /// 104.33pt down a 402×624.67 plane. The plane's region must keep the
    /// window's own degrees-per-point (no vertical stretch) and put every
    /// window point at the same coordinate it had before.
    @Test func planeRegionExtendsTheWindowRegionWithoutChangingItsScale() {
        let window = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.7736, longitude: -73.9566),
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.017)
        )
        let windowFrame = CGRect(x: 0, y: 104.33, width: 402, height: 374.67)
        let planeSize = CGSize(width: 402, height: 624.67)
        let plane = CafeMapScreen.planeRegion(windowRegion: window, windowFrame: windowFrame, planeSize: planeSize)

        #expect(abs(plane.span.latitudeDelta / 624.67 - window.span.latitudeDelta / 374.67) < 1e-12)
        #expect(abs(plane.span.longitudeDelta - window.span.longitudeDelta) < 1e-12)

        // The window's centre coordinate lands at the window's centre POINT
        // in plane space, and its top edge at the window's top.
        let projector = ScreenProjector(region: plane, size: planeSize)
        let centre = projector.point(for: window.center)
        #expect(abs(centre.x - windowFrame.midX) < 0.01 && abs(centre.y - windowFrame.midY) < 0.01)
        let top = projector.point(for: CLLocationCoordinate2D(
            latitude: window.center.latitude + window.span.latitudeDelta / 2, longitude: window.center.longitude
        ))
        #expect(abs(top.y - windowFrame.minY) < 0.01)
    }

    @Test func planeRegionIsTheIdentityWhenTheWindowIsThePlaneOrUnmeasured() {
        let window = region()
        let size = CGSize(width: 390, height: 660)
        let same = CafeMapScreen.planeRegion(windowRegion: window, windowFrame: CGRect(origin: .zero, size: size), planeSize: size)
        #expect(abs(same.center.latitude - window.center.latitude) < 1e-9)
        #expect(abs(same.span.latitudeDelta - window.span.latitudeDelta) < 1e-9)
        #expect(abs(same.span.longitudeDelta - window.span.longitudeDelta) < 1e-9)
        let unmeasured = CafeMapScreen.planeRegion(windowRegion: window, windowFrame: .zero, planeSize: size)
        #expect(unmeasured.span.latitudeDelta == window.span.latitudeDelta && unmeasured.center.latitude == window.center.latitude)
    }
}
