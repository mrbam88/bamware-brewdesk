import CoreGraphics
import MapKit
import VenueKit

/// What a single venue's marker should draw as right now (bd#212 "micro
/// teardrops" — replaces the old pin/dot/cluster-stack three-representation
/// model outright; there is no grouping of any kind left in the app).
///
/// Only `.teardrop` is a real SwiftUI `Annotation`/`Button` — `.dot` and
/// `.speck` are drawn as native MapKit `MapCircle` overlay content by
/// `CafeMapScreen` (supervisor review of the first micro-teardrops pass:
/// ~200 unrated specks as full SwiftUI annotation views, each wrapped in a
/// 44pt `Button`, was the actual cost behind the missed hitchRatio target —
/// a `MapCircle` is MapKit's own cheap overlay primitive, never a hosted
/// SwiftUI view at all).
public enum MarkerKind: Equatable, Sendable {
    /// Full teardrop, tip on the coordinate. `diameter` is the head
    /// diameter in points; the number renders only when the CALLER'S
    /// `showsNumber` is also true (see `MarkerPlacement`).
    case teardrop(diameter: CGFloat)
    /// A plain tier-colored `MapCircle`, never numbered — either the zoom
    /// is too far out for a teardrop shape at all, or this candidate lost a
    /// screen-space collision to a better-scored teardrop and was demoted
    /// (bd#212's overlap rule). Fixed real-world radius — see
    /// `CafeMapScreen.demotedDotRadiusMeters`.
    case dot
    /// A faint, neutral `MapCircle` for an UNRATED (unobserved) venue —
    /// never tier-colored (bd#159's rule carried into bd#212). Fixed
    /// real-world radius — see `CafeMapScreen.speckRadiusMeters`.
    case speck

    /// Only a `.teardrop` has a caller-chosen point-size; `.dot`/`.speck`
    /// are sized in real-world meters by the view layer instead.
    var teardropDiameter: CGFloat? {
        if case let .teardrop(diameter) = self { diameter } else { nil }
    }
}

/// One venue's fully-resolved marker for this `plan()` call (bd#212).
///
/// `id` is always the venue id. A venue's kind/diameter/selection state can
/// all change between two `plan()` calls (a re-plan after a camera settle,
/// a new selection) without ever changing this id — within each of
/// `CafeMapScreen`'s three `ForEach`s (teardrops/dots/specks) this keeps
/// MapKit updating the SAME hosted content in place rather than tearing it
/// down and rebuilding it. (A venue crossing a KIND boundary — e.g. a
/// teardrop losing a fresh collision and demoting to a dot — does move
/// between those three `ForEach`s, a real remove+insert; that's an accepted
///, relatively rare trade-off for keeping the steady-state cost of ~150-200
/// unrated specks at native-overlay prices instead of SwiftUI-annotation
/// prices.)
/// bd#221: which side of its own head a teardrop's café-name label sits on
/// — decided once, deterministically, by the planner (screen space), never
/// by the view. `nil` on `MarkerPlacement` means "no label" (not eligible,
/// zoomed too far out, or lost every placement attempt this plan).
public enum NameLabelSide: Equatable, Sendable {
    case trailing
    case leading
}

public struct MarkerPlacement: Identifiable, Equatable, Sendable {
    public let venue: Venue
    public let kind: MarkerKind
    /// True only for a full (never demoted) teardrop at `diameter >= 11` —
    /// a demoted dot never shows a number, even though it's still "rated"
    /// (bd#212 spec: "The score number shows only when the head is ≥ 11
    /// pt").
    public let showsNumber: Bool
    public let isSelected: Bool
    /// bd#221 "names on": which side (if any) this marker's café-name label
    /// should render on, decided once by `MapAnnotationPlanner.plan(...)`.
    /// Always `nil` for the selected marker (it carries its own name above
    /// the halo instead) and for anything below the number threshold.
    public let nameLabelSide: NameLabelSide?

    public var id: String { venue.id }

    public init(
        venue: Venue, kind: MarkerKind, showsNumber: Bool, isSelected: Bool = false,
        nameLabelSide: NameLabelSide? = nil
    ) {
        self.venue = venue
        self.kind = kind
        self.showsNumber = showsNumber
        self.isSelected = isSelected
        self.nameLabelSide = nameLabelSide
    }
}

/// What the map should draw for the current venues + camera (brewdesk#54,
/// re-shaped bd#204/#209, replaced outright by bd#212's micro-teardrop
/// design — no clusters/stacks/counts of any kind remain). Representation
/// only — no styling; views decide what a teardrop/dot/speck looks like
/// (`MapAnnotationViews`/`CafeMapScreen`) without touching this logic.
public struct MapAnnotationPlan: Equatable, Sendable {
    public let markers: [MarkerPlacement]

    public init(markers: [MarkerPlacement]) {
        self.markers = markers
    }

    public var annotationCount: Int { markers.count }

    public func containsVenue(id: String) -> Bool {
        markers.contains { $0.id == id }
    }

    /// Full teardrops — the only kind hosted as a real SwiftUI `Annotation`.
    public var teardrops: [MarkerPlacement] { markers.filter { if case .teardrop = $0.kind { true } else { false } } }
    /// Demoted rated venues — drawn as a native `MapCircle`.
    public var dots: [MarkerPlacement] { markers.filter { $0.kind == .dot } }
    /// Unrated venues — drawn as a native `MapCircle`.
    public var specks: [MarkerPlacement] { markers.filter { $0.kind == .speck } }
}

/// Pure, unit-tested planning: viewport culling with a margin, then a
/// zoom-driven size + screen-space collision-free layout (bd#212). Never
/// called mid-gesture — the map screen re-plans only when a camera move
/// ends (`.onMapCameraChange(frequency: .onEnd)`).
public enum MapAnnotationPlanner {
    /// Hard ceiling on total rendered annotations — rated venues first,
    /// then the nearest unrated specks fill whatever budget is left
    /// (bd#212 spec: "~220 annotations").
    public static let maxAnnotations = 220
    /// How many unrated candidates (nearest-to-centre) are even considered
    /// once every rated venue has been placed.
    public static let unratedCandidateLimit = 150
    /// Extra region kept annotated on every side (fraction of the span), so
    /// a pan shorter than half a screen never uncovers un-annotated map.
    public static let cullMargin = 0.5
    /// Map-view size used for screen-space collision/metres-per-point math
    /// when the real `mapSize` hasn't been measured yet (the very first
    /// `plan()` call, one frame before `CafeMapScreen`'s `GeometryReader`
    /// reports a real size).
    public static let fallbackMapSize = CGSize(width: 390, height: 660)
    /// Shared margin added around a teardrop's own head before two
    /// footprints are tested for overlap. Supervisor review: the footprint
    /// must be the REAL head size, not a generous collision box — "head
    /// diameter + 1pt, tail excluded from the box" — since `.dot`/`.speck`
    /// are no longer discrete competing widgets (they're translucent
    /// `MapCircle` overlays MapKit draws natively), the ONLY thing that
    /// still needs strict AABB collision is teardrop-vs-teardrop (and
    /// teardrop-vs-exclusion-rect); a tight box means fewer venues demote
    /// in a genuinely dense neighbourhood, matching the reference mock's
    /// density of numbered pins.
    public static let footprintPadding: CGFloat = 0.5
    /// Total marker HEIGHT as a multiple of head diameter, for VIEW sizing
    /// only (`TeardropMarkerView`'s outer frame) — head circle (1.0×) plus
    /// the tail's natural extent under the CSS-style rotated-square
    /// construction (`TeardropShape`): a 45°-rotated square's far corner
    /// sits `0.5 + 0.5·√2 ≈ 1.2071`× the side away from the near corner.
    /// NOT used for collision any more (see `footprintPadding`) — the tail
    /// is deliberately excluded from the collision box.
    public static let tailHeightFactor: CGFloat = 1.21

    // MARK: - bd#212 (supervisor revision): metres-per-point sizing

    /// (metres/point, head diameter) control points, widest (most zoomed
    /// out) first. Keying off real-world metres-per-screen-point — rather
    /// than the requested `MKCoordinateRegion` span in degrees — survives
    /// the phone's actual aspect ratio: MapKit fits the REQUESTED region to
    /// the view, so the rendered span can end up larger than what was asked
    /// for; metres/point is measured from the SETTLED camera and the map's
    /// own width, so it's always the real, on-screen answer. Interpolated
    /// on a LOG scale (each stop here is exactly half the previous one, a
    /// natural fit for "zoom level" style progressions), clamped past
    /// either end.
    private static let sizeStopsByMetersPerPoint: [(mpp: Double, diameter: CGFloat)] = [
        // Supervisor review 2026-09-20: the first cut (7.2→4, 3.6→12) fell
        // under `numberThreshold` as soon as a real phone's neighborhood
        // view was slightly wider than 3.6 m/pt (MapKit fits the region to
        // the screen's aspect), so every café became a dot. Numbered
        // teardrops now hold through a normal neighborhood view (~5.4 m/pt,
        // ≈ 2.1 km across) and only then shrink to pin-pricks.
        //
        // bd#221 (Bilal's round-2 pin selection, "microscopical bigger"):
        // +1pt at every NUMBERED stop — the 9.0→4 "no number" floor is
        // unchanged. Matches the design-review page's `size:"microplus"`
        // selection exactly (`SIZES.microplus` in the prototype).
        (9.0, 4), (5.4, 12.5), (3.6, 13.5), (1.8, 18), (0.9, 21),
    ]
    /// Beyond this many metres/point an unrated speck draws nothing at all
    /// (too zoomed out to mean anything).
    public static let speckVisibilityThresholdMetersPerPoint: Double = 5.0
    /// A teardrop shape needs enough pixels for the round head PLUS the
    /// pointed tail to read as a pin rather than a blob — below this the
    /// design intentionally "degrades to a plain dot" (spec's own words).
    public static let teardropShapeThreshold: CGFloat = 10
    /// The number never shows below this head diameter, even on a full
    /// (non-demoted) teardrop.
    public static let numberThreshold: CGFloat = 11
    /// Selected marker: fixed size regardless of zoom (bd#212 spec).
    public static let selectedDiameter: CGFloat = 30

    // MARK: - bd#221: café-name labels ("names on")

    /// Gap between a head's edge and its name label (design-review mock's
    /// own value, `stylePin`'s label block).
    static let labelGap: CGFloat = 4
    /// Fixed box height a label collision-checks against — one line of
    /// 11pt Hanken Grotesk Semibold plus a hair of vertical breathing room.
    static let labelBoxHeight: CGFloat = 14
    /// Widest a label may render, tail-truncated beyond this (mock's own
    /// `Math.min(132, …)`).
    public static let labelMaxWidth: CGFloat = 132
    /// Cheap per-character width estimate (mock's own `n.length*5.9+4`) —
    /// good enough for a deterministic, allocation-free layout pass; the
    /// view still truncates with `.lineLimit(1)` if this ever under-shoots
    /// a real glyph's width.
    static let labelCharWidth: CGFloat = 5.9
    static let labelPadding: CGFloat = 4
    /// Vertical distance from a teardrop's TIP (the coordinate the planner
    /// projects to screen space) up to its HEAD's own center — the closed
    /// form of `TeardropShape`'s geometry: tip sits `frameHeight` from the
    /// head's top edge, head center sits `diameter/2` from that same top
    /// edge, so tip-to-center is `diameter · (tailHeightFactor - 0.5)`.
    /// Matches `TeardropMarkerView.numberVerticalOffset`'s own geometry.
    static let headCenterFromTip: CGFloat = tailHeightFactor - 0.5
    /// Below this many metres/point the viewport reads as "street" scale
    /// (12 labels); at or above it, "neighborhood" scale (8 labels) — the
    /// midpoint between the two reference zooms the spec names explicitly
    /// (3.6 m/pt neighborhood, 1.8 m/pt street).
    public static let labelStreetScaleMpp: Double = 2.7
    public static let labelCountNeighborhood = 8
    public static let labelCountStreet = 12

    /// bd#221 "names on": mutates `placed` in place, attaching a
    /// `nameLabelSide` to whichever already-placed teardrops win a
    /// collision-free label slot. Runs entirely in screen space, after
    /// every pin this `plan()` call will ever draw already exists — a
    /// label can never bump a pin out of its slot, only occupy space a pin
    /// left free.
    /// Screen-edge margin a label box must clear — matches the design-
    /// review mock's own `lx<6||lx+tw>W-6` guard. Without this a label
    /// beside a pin near the map's own left/right edge can render partly
    /// off-screen (clipped by the device bezel, not by our own
    /// truncation) instead of trying the OTHER side or being omitted.
    private static let labelScreenMargin: CGFloat = 6

    private static func placeNameLabels(
        into placed: inout [MarkerPlacement], grid: CollisionGrid, headBoxes: [AABB], projector: ScreenProjector,
        diameter: CGFloat, mpp: Double, mapSize: CGSize
    ) {
        guard diameter >= numberThreshold else { return }
        let limit = mpp <= labelStreetScaleMpp ? labelCountStreet : labelCountNeighborhood
        let eligibleIndices = placed.indices.filter { index in
            let m = placed[index]
            return !m.isSelected && m.showsNumber && m.kind.teardropDiameter != nil
        }
        // `placed` is already score-descending for rated teardrops (the
        // selected venue, if any, is index 0 and excluded above), so
        // `eligibleIndices` is too. Supervisor review (bd#221 round 2):
        // this used to `.prefix(limit)` the CANDIDATE pool — i.e. only
        // ever ATTEMPT the top `limit` scored venues — so a dense cluster
        // could lose several of the very best-scored candidates to
        // collisions and end up with fewer labels than `limit`, while
        // never giving the next-best-scored venues (rank `limit+1`,
        // `limit+2`, …) a chance to fill those slots. `limit` is a target
        // COUNT OF SUCCESSFUL PLACEMENTS, not a candidate cutoff — keep
        // walking the score-ranked list until `limit` labels actually
        // land or candidates run out.
        var placedCount = 0
        for index in eligibleIndices {
            guard placedCount < limit else { break }
            let venue = placed[index].venue
            let point = projector.point(for: coordinate(of: venue))
            let headCenter = CGPoint(x: point.x, y: point.y - diameter * headCenterFromTip)
            let width = min(labelMaxWidth, CGFloat(venue.name.count) * labelCharWidth + labelPadding)
            let halfHeight = labelBoxHeight / 2
            let attempts: [(NameLabelSide, CGRect)] = [
                (.trailing, CGRect(
                    x: headCenter.x + diameter / 2 + labelGap, y: headCenter.y - halfHeight,
                    width: width, height: labelBoxHeight
                )),
                (.leading, CGRect(
                    x: headCenter.x - diameter / 2 - labelGap - width, y: headCenter.y - halfHeight,
                    width: width, height: labelBoxHeight
                )),
            ]
            for (side, rect) in attempts {
                guard rect.minX >= labelScreenMargin, rect.maxX <= mapSize.width - labelScreenMargin else { continue }
                let box = AABB(minX: rect.minX, maxX: rect.maxX, minY: rect.minY, maxY: rect.maxY)
                guard !grid.collides(box) else { continue }
                // `grid` alone isn't enough — see `headBoxes`' own doc
                // comment in `plan()`: its footprints are tip-centered and
                // under-cover a neighbour's TRUE visual head, so a label
                // that clears `grid` can still visually run through part
                // of a nearby pin's actual circle.
                guard !headBoxes.contains(where: { $0.intersects(box) }) else { continue }
                grid.insert(box)
                let m = placed[index]
                placed[index] = MarkerPlacement(
                    venue: m.venue, kind: m.kind, showsNumber: m.showsNumber, isSelected: m.isSelected,
                    nameLabelSide: side
                )
                placedCount += 1
                break
            }
        }
    }

    /// Piecewise LOG-scale interpolation over `sizeStopsByMetersPerPoint`,
    /// clamped at both ends — a smaller metres/point (more zoomed in)
    /// always yields a diameter >= a larger one's, by construction.
    private static func interpolateLog(_ stops: [(mpp: Double, diameter: CGFloat)], mpp: Double) -> CGFloat {
        guard let first = stops.first, let last = stops.last, mpp > 0 else { return stops.first?.diameter ?? 0 }
        if mpp >= first.mpp { return first.diameter }
        if mpp <= last.mpp { return last.diameter }
        for i in 0..<(stops.count - 1) {
            let hi = stops[i]
            let lo = stops[i + 1]
            guard mpp <= hi.mpp, mpp >= lo.mpp else { continue }
            let t = (log(hi.mpp) - log(mpp)) / (log(hi.mpp) - log(lo.mpp))
            return hi.diameter + (lo.diameter - hi.diameter) * CGFloat(t)
        }
        return last.diameter
    }

    /// Head diameter (points) for a RATED venue's marker at this real,
    /// settled metres-per-screen-point, before any collision demotion.
    public static func headDiameter(forMetersPerPoint mpp: Double) -> CGFloat {
        interpolateLog(sizeStopsByMetersPerPoint, mpp: mpp)
    }

    /// Real-world metres spanned by one screen point at the settled camera
    /// — (visible width in metres) / (map width in points). This is what
    /// the phone's user actually SEES, unlike the requested region span,
    /// which MapKit may render wider than asked once it fits the view's
    /// aspect ratio.
    public static func metersPerPoint(region: MKCoordinateRegion, mapWidth: CGFloat) -> Double {
        guard mapWidth > 0 else { return 3.3 }
        let metersPerDegreeLongitude = 111_320.0 * cos(region.center.latitude * .pi / 180)
        let visibleWidthMeters = region.span.longitudeDelta * abs(metersPerDegreeLongitude)
        return visibleWidthMeters / Double(mapWidth)
    }

    // MARK: - Plan

    /// - Parameters:
    ///   - mapSize: the map view's current size in points.
    ///   - selectedVenueID: always rendered as the fixed 30pt selected
    ///     teardrop, seeded into the collision grid first so nothing may
    ///     ever be placed on top of it.
    ///   - exclusionRects: screen-space rects already "occupied" before any
    ///     TEARDROP is placed (bd#210, extended bd#217) — the search
    ///     header, "Search this area" pill, compass, locate button, shelf
    ///     card. `.speck` markers are native `MapCircle` overlays and are
    ///     never checked against these — a faint, unrated, never-numbered
    ///     indicator sitting briefly under chrome isn't the same problem a
    ///     hidden, un-tappable teardrop was.
    ///
    ///     bd#217: a RATED candidate whose teardrop attempt collides with
    ///     one of these rects is now SKIPPED outright rather than falling
    ///     back to a `.dot` — the bd#210 rule inserted these rects into the
    ///     same collision grid as every teardrop, which correctly kept the
    ///     TEARDROP off the chrome, but the fallback `.dot` for that same
    ///     losing candidate still rendered at the identical coordinate,
    ///     because `.dot`s (a native `MapCircle`, drawn independently by
    ///     `CafeMapScreen`) were never themselves exclusion-checked. That
    ///     was the exact TestFlight build 26 bug: a small green dot peeking
    ///     out from under the "Search this area" pill where its would-be
    ///     teardrop had just been correctly excluded. A candidate demoted
    ///     by a SIBLING teardrop (no chrome involved) still falls back to a
    ///     dot as before — only a chrome collision skips the venue for this
    ///     plan entirely.
    /// - Parameter region: the current camera viewport, or `nil` when it has
    ///   never been observed. A stale/unknown region must never render as an
    ///   empty plan while `venues` is non-empty (brewdesk#157) — falls back
    ///   to the un-culled venue list, every one a full (un-demoted) teardrop
    ///   at the "closest" diameter, rather than trusting pixel math against
    ///   a region already known to be wrong.
    public static func plan(
        venues: [Venue],
        region: MKCoordinateRegion?,
        mapSize: CGSize = .zero,
        selectedVenueID: String? = nil,
        exclusionRects: [CGRect] = []
    ) -> MapAnnotationPlan {
        guard let region else {
            let markers = venues.map {
                MarkerPlacement(
                    venue: $0,
                    kind: .teardrop(diameter: sizeStopsByMetersPerPoint.last!.diameter),
                    // brewdesk#213: `isRated` honors the server's explicit
                    // `scoreDisplay` over the `isObserved` heuristic.
                    showsNumber: $0.isRated,
                    isSelected: $0.id == selectedVenueID
                )
            }
            return MapAnnotationPlan(markers: markers)
        }
        let culledVenues = culled(venues, region: region)
        let visible = (culledVenues.isEmpty && !venues.isEmpty) ? venues : culledVenues
        guard !visible.isEmpty else { return MapAnnotationPlan(markers: []) }

        let size = (mapSize.width > 0 && mapSize.height > 0) ? mapSize : fallbackMapSize
        let projector = ScreenProjector(region: region, size: size)
        // Only teardrops (and chrome exclusion rects) ever enter the
        // collision grid — see `footprintPadding`'s doc comment.
        let grid = CollisionGrid()
        // bd#217: kept as its own list, separate from `grid`, so a losing
        // candidate can be asked "did I lose specifically to CHROME?" — see
        // the chrome-skip check in the rated-venue loop below.
        let exclusionBoxes = exclusionRects.map {
            AABB(minX: $0.minX, maxX: $0.maxX, minY: $0.minY, maxY: $0.maxY)
        }
        for box in exclusionBoxes {
            grid.insert(box)
        }

        let mpp = metersPerPoint(region: region, mapWidth: size.width)
        let ratedDiameter = headDiameter(forMetersPerPoint: mpp)
        let speckVisible = mpp <= speckVisibilityThresholdMetersPerPoint

        var placed: [MarkerPlacement] = []
        var totalPlaced = 0
        // bd#221 "names on" — TRUE visual head boxes (headCenter ± radius),
        // separate from `grid`'s own teardrop footprints (which are
        // centered on the TIP, per `teardropFootprint`'s own doc comment —
        // "head diameter + 1pt" measured from the coordinate, not from the
        // shape's actual visual center). A teardrop's real circular head
        // sits `diameter · headCenterFromTip` ABOVE its tip, which the
        // tip-centered footprint only partially covers — fine for
        // teardrop-vs-teardrop spacing (every pin uses the same
        // convention, so relative spacing stays conservative), but a
        // label placed to CLEAR that footprint could still visually
        // overlap a neighbour's real head above it. Supervisor review
        // (bd#221 round 2) caught exactly this: a label sitting flush
        // against `grid`'s footprint boundary still drew through part of
        // the next pin's head. Checked ADDITIONALLY, alongside `grid`, in
        // `placeNameLabels` — this never changes teardrop-vs-teardrop
        // placement itself, only what a LABEL is allowed to sit under.
        var headBoxes: [AABB] = []
        func headBox(diameter: CGFloat, tip: CGPoint) -> AABB {
            let center = CGPoint(x: tip.x, y: tip.y - diameter * headCenterFromTip)
            let radius = diameter / 2
            return AABB(minX: center.x - radius, maxX: center.x + radius, minY: center.y - radius, maxY: center.y + radius)
        }

        // 1. Selected venue — highest priority, always a full teardrop at
        // the fixed 30pt size, seeded before anything else.
        var selectedVenue: Venue?
        if let selectedVenueID, let match = visible.first(where: { $0.id == selectedVenueID }) {
            let point = projector.point(for: coordinate(of: match))
            let box = teardropFootprint(diameter: selectedDiameter, at: point)
            grid.insert(box)
            headBoxes.append(headBox(diameter: selectedDiameter, tip: point))
            placed.append(
                MarkerPlacement(
                    venue: match,
                    kind: .teardrop(diameter: selectedDiameter),
                    showsNumber: match.isRated,
                    isSelected: true
                )
            )
            totalPlaced += 1
            selectedVenue = match
        }

        // 2. Rated (observed) venues, best score first. Below the shape
        // threshold, every rated venue is simply a dot — no teardrop is
        // even attempted, so no collision work happens at all at that
        // zoom. At/above the threshold, each candidate competes for a full
        // teardrop; a screen-space collision demotes it to a dot instead
        // of dropping it (bd#212's overlap rule) — a dot is a cheap
        // `MapCircle`, never itself collision-checked, so no rated venue is
        // ever silently hidden by this pass any more.
        let rated = visible
            .filter { $0.isRated && $0.id != selectedVenue?.id }
            .sorted(by: byScoreDescendingThenID)
        let attemptTeardrops = ratedDiameter >= teardropShapeThreshold
        for candidate in rated {
            guard totalPlaced < maxAnnotations else { break }
            if attemptTeardrops {
                let point = projector.point(for: coordinate(of: candidate))
                let teardropBox = teardropFootprint(diameter: ratedDiameter, at: point)
                if !grid.collides(teardropBox) {
                    grid.insert(teardropBox)
                    headBoxes.append(headBox(diameter: ratedDiameter, tip: point))
                    placed.append(MarkerPlacement(
                        venue: candidate,
                        kind: .teardrop(diameter: ratedDiameter),
                        showsNumber: ratedDiameter >= numberThreshold
                    ))
                    totalPlaced += 1
                    continue
                }
                // bd#217: a chrome collision skips the venue entirely this
                // plan — see `plan`'s own doc comment on `exclusionRects`
                // for why a `.dot` fallback here would just reproduce the
                // same peeking-out-from-under-the-pill bug at a smaller
                // size. A SIBLING-teardrop collision (no exclusion rect
                // involved) still falls through to the dot fallback below.
                if exclusionBoxes.contains(where: { $0.intersects(teardropBox) }) {
                    continue
                }
            }
            placed.append(MarkerPlacement(venue: candidate, kind: .dot, showsNumber: false))
            totalPlaced += 1
        }

        // 2b. bd#221 "names on" — café-name labels beside the best-scored
        // numbered teardrops (Apple POI label style). Computed AFTER every
        // pin above is already placed: labels are pure decoration and must
        // never cause a pin to demote (spec's own rule) — this pass only
        // ever appends to `grid`, it never removes or re-checks a pin.
        placeNameLabels(into: &placed, grid: grid, headBoxes: headBoxes, projector: projector, diameter: ratedDiameter, mpp: mpp, mapSize: size)

        // 3. Unrated (unobserved) venues — faint neutral specks, nearest-
        // to-centre first, never numbered, never tier-colored, never
        // collision-checked (native `MapCircle` overlays render fine
        // overlapping each other).
        if speckVisible {
            let unratedEligible = visible.filter { !$0.isRated && $0.id != selectedVenue?.id }
            let nearest = nearestToCentre(unratedEligible, region: region, limit: unratedCandidateLimit)
            for candidate in nearest {
                guard totalPlaced < maxAnnotations else { break }
                placed.append(MarkerPlacement(venue: candidate, kind: .speck, showsNumber: false))
                totalPlaced += 1
            }
        }

        return MapAnnotationPlan(markers: placed)
    }

    private static func coordinate(of venue: Venue) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: venue.lat, longitude: venue.lng)
    }

    private static func byScoreDescendingThenID(_ lhs: Venue, _ rhs: Venue) -> Bool {
        lhs.workScore != rhs.workScore ? lhs.workScore > rhs.workScore : lhs.id < rhs.id
    }

    /// A teardrop's collision footprint: the real head size (diameter +
    /// 1pt padding on every side), tail deliberately excluded — see
    /// `footprintPadding`'s doc comment.
    static func teardropFootprint(diameter: CGFloat, at point: CGPoint) -> AABB {
        let side = diameter + footprintPadding * 2
        return AABB(
            minX: point.x - side / 2, maxX: point.x + side / 2,
            minY: point.y - side / 2, maxY: point.y + side / 2
        )
    }

    /// Venues inside the region padded by `cullMargin` on every side.
    /// Order is preserved (the model ranks by Work Fit).
    public static func culled(_ venues: [Venue], region: MKCoordinateRegion) -> [Venue] {
        let latPad = region.span.latitudeDelta * cullMargin
        let lngPad = region.span.longitudeDelta * cullMargin
        let minLat = region.center.latitude - region.span.latitudeDelta / 2 - latPad
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2 + latPad
        let minLng = region.center.longitude - region.span.longitudeDelta / 2 - lngPad
        let maxLng = region.center.longitude + region.span.longitudeDelta / 2 + lngPad
        return venues.filter {
            $0.lat >= minLat && $0.lat <= maxLat && $0.lng >= minLng && $0.lng <= maxLng
        }
    }

    /// Nearest `limit` venues to the region's centre, ties broken by id.
    private static func nearestToCentre(_ venues: [Venue], region: MKCoordinateRegion?, limit: Int) -> [Venue] {
        guard let center = region?.center else { return Array(venues.prefix(limit)) }
        func distanceSquared(_ venue: Venue) -> Double {
            let dLat = venue.lat - center.latitude
            let dLng = venue.lng - center.longitude
            return dLat * dLat + dLng * dLng
        }
        return Array(
            venues
                .sorted { lhs, rhs in
                    let lhsD = distanceSquared(lhs)
                    let rhsD = distanceSquared(rhs)
                    return lhsD != rhsD ? lhsD < rhsD : lhs.id < rhs.id
                }
                .prefix(limit)
        )
    }
}

// MARK: - bd#209/#212: screen projection, collision grid

/// Linear (equirectangular) mapping between a `MKCoordinateRegion` and a
/// view's point space — accurate enough at city scale.
struct ScreenProjector {
    let region: MKCoordinateRegion
    let size: CGSize

    private var minLat: Double { region.center.latitude - region.span.latitudeDelta / 2 }
    private var minLng: Double { region.center.longitude - region.span.longitudeDelta / 2 }
    private var latSpan: Double { max(region.span.latitudeDelta, 1e-9) }
    private var lngSpan: Double { max(region.span.longitudeDelta, 1e-9) }

    func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
        let x = (coordinate.longitude - minLng) / lngSpan * Double(size.width)
        // Screen y grows downward; latitude grows northward (upward) — flip.
        let y = (1 - (coordinate.latitude - minLat) / latSpan) * Double(size.height)
        return CGPoint(x: x, y: y)
    }
}

/// Axis-aligned bounding box used as every teardrop's collision footprint.
struct AABB {
    var minX, maxX, minY, maxY: CGFloat

    func intersects(_ other: AABB) -> Bool {
        minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY
    }
}

/// Uniform grid spatial hash over already-placed footprints, so a new
/// candidate is checked against only its own neighbourhood instead of every
/// prior marker — `plan()` stays O(n) even at a 500-venue dense viewport.
final class CollisionGrid {
    private let cellSize: CGFloat = 48
    private var buckets: [Int64: [Int]] = [:]
    private var boxes: [AABB] = []

    private func key(_ cx: Int, _ cy: Int) -> Int64 {
        Int64(cx) &* 1_000_003 &+ Int64(cy)
    }

    private func span(of box: AABB) -> (minCX: Int, maxCX: Int, minCY: Int, maxCY: Int) {
        (
            Int(floor(box.minX / cellSize)), Int(floor(box.maxX / cellSize)),
            Int(floor(box.minY / cellSize)), Int(floor(box.maxY / cellSize))
        )
    }

    func collides(_ box: AABB) -> Bool {
        let bounds = span(of: box)
        for cx in bounds.minCX...bounds.maxCX {
            for cy in bounds.minCY...bounds.maxCY {
                guard let indices = buckets[key(cx, cy)] else { continue }
                for i in indices where boxes[i].intersects(box) { return true }
            }
        }
        return false
    }

    func insert(_ box: AABB) {
        let index = boxes.count
        boxes.append(box)
        let bounds = span(of: box)
        for cx in bounds.minCX...bounds.maxCX {
            for cy in bounds.minCY...bounds.maxCY {
                buckets[key(cx, cy), default: []].append(index)
            }
        }
    }
}
