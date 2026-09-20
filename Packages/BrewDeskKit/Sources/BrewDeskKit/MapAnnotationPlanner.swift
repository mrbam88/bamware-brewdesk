import CoreGraphics
import MapKit
import VenueKit

/// What shape/size a single venue's marker should draw as right now
/// (bd#212 "micro teardrops" — replaces the old pin/dot/cluster-stack
/// three-representation model outright; there is no grouping of any kind
/// left in the app).
public enum MarkerKind: Equatable, Sendable {
    /// Full teardrop, tip on the coordinate. `diameter` is the head
    /// diameter in points; the number renders only when the CALLER'S
    /// `showsNumber` is also true (see `MarkerPlacement`).
    case teardrop(diameter: CGFloat)
    /// A plain filled circle, tier-colored like a teardrop but never
    /// numbered — either because the zoom is too far out for a teardrop
    /// shape at all, or because this candidate lost a screen-space
    /// collision to a better-scored marker and was demoted (bd#212's
    /// overlap rule).
    case dot(diameter: CGFloat)
    /// A faint, neutral, never-numbered mark for an UNRATED (unobserved)
    /// venue — never tier-colored (bd#159's rule carried into bd#212).
    case speck(diameter: CGFloat)

    var diameter: CGFloat {
        switch self {
        case let .teardrop(d), let .dot(d), let .speck(d): d
        }
    }
}

/// One venue's fully-resolved marker for this `plan()` call (bd#212).
///
/// `id` is always the venue id — the ONE stable identity every annotation
/// in `CafeMapScreen`'s `ForEach` keys off. A venue's kind/diameter/
/// selection state can all change between two `plan()` calls (a re-plan
/// after a camera settle, a new selection) without ever changing this id,
/// which is what lets MapKit update the SAME annotation view in place
/// instead of destroying and recreating it — the direct fix for the #211
/// stalls (70-100 annotation views being torn down and rebuilt on every
/// re-plan).
public struct MarkerPlacement: Identifiable, Equatable, Sendable {
    public let venue: Venue
    public let kind: MarkerKind
    /// True only for a full (never demoted) teardrop at `diameter >= 11` —
    /// a demoted dot or a below-threshold teardrop never shows a number,
    /// even if it's technically still "rated" (bd#212 spec: "The score
    /// number shows only when the head is ≥ 11 pt").
    public let showsNumber: Bool
    public let isSelected: Bool

    public var id: String { venue.id }

    public init(venue: Venue, kind: MarkerKind, showsNumber: Bool, isSelected: Bool = false) {
        self.venue = venue
        self.kind = kind
        self.showsNumber = showsNumber
        self.isSelected = isSelected
    }
}

/// What the map should draw for the current venues + camera (brewdesk#54,
/// re-shaped bd#204/#209, replaced outright by bd#212's micro-teardrop
/// design — no clusters/stacks/counts of any kind remain). Representation
/// only — no styling; views decide what a teardrop/dot/speck looks like
/// (`MapAnnotationViews`) without touching this logic.
public struct MapAnnotationPlan: Equatable, Sendable {
    public let markers: [MarkerPlacement]

    public init(markers: [MarkerPlacement]) {
        self.markers = markers
    }

    public var annotationCount: Int { markers.count }

    public func containsVenue(id: String) -> Bool {
        markers.contains { $0.id == id }
    }
}

/// Pure, unit-tested planning: viewport culling with a margin, then a
/// zoom-driven size + screen-space collision-free layout (bd#212). Never
/// called mid-gesture — the map screen re-plans only when a camera move
/// ends (`.onMapCameraChange(frequency: .onEnd)`).
public enum MapAnnotationPlanner {
    /// Hard ceiling on total rendered annotations — rated venues first,
    /// then the nearest unrated specks fill whatever budget is left
    /// (bd#212 spec: "~220 annotations"). Direct descendant of #209/#211's
    /// `maxAnnotations` — same purpose (bound the perf-critical annotation
    /// count), raised because bd#212 draws EVERY rated venue individually
    /// (no stack ever absorbs overflow any more).
    public static let maxAnnotations = 220
    /// How many unrated candidates (nearest-to-centre) are even considered
    /// once every rated venue has been placed — bounds the collision-check
    /// work the same way the old `dotCandidateLimit` did.
    public static let unratedCandidateLimit = 150
    /// Extra region kept annotated on every side (fraction of the span), so
    /// a pan shorter than half a screen never uncovers un-annotated map.
    public static let cullMargin = 0.5
    /// Map-view size used for screen-space collision math when the real
    /// `mapSize` hasn't been measured yet (the very first `plan()` call, one
    /// frame before `CafeMapScreen`'s `GeometryReader` reports a real size).
    public static let fallbackMapSize = CGSize(width: 390, height: 660)
    /// Shared margin added around every marker's own visual size before two
    /// footprints are tested for overlap. Tuned down from an initial 3pt
    /// after a live-density screenshot check at hood zoom in West Village
    /// (real production data): the first pass's generous padding plus a
    /// 1.3x-diameter tail allowance demoted nearly every marker to an
    /// unnumbered dot in a genuinely dense neighborhood, which undersells
    /// the whole point of the redesign (real café evidence visible, not
    /// hidden behind demotion). 1.5pt still guarantees a visible gap
    /// between two adjacent markers' hairline edges.
    public static let footprintPadding: CGFloat = 1.5
    /// Total marker height as a multiple of head diameter (head circle +
    /// tail) — the SAME factor `TeardropMarkerView`'s outer frame uses, so
    /// the collision footprint always matches what's actually drawn.
    /// Lowered from an initial 1.3 alongside `footprintPadding` (see its
    /// comment) — a shorter, stubbier tail reads fine at these sizes and
    /// keeps two nearby markers from fighting over vertical room they don't
    /// visually need.
    public static let tailHeightFactor: CGFloat = 1.1

    // MARK: - bd#212: zoom-driven sizing

    /// (span, head diameter) control points, widest span first — see the
    /// design record: zoomed out (≥0.045°) draws a plain 4pt dot with no
    /// number, all the way to "closest" (≤0.005°) at a 20pt max head.
    /// Smoothly interpolated between points, clamped past either end.
    private static let sizeStops: [(span: Double, diameter: CGFloat)] = [
        (0.045, 4), (0.022, 12), (0.011, 17), (0.005, 20),
    ]
    /// (span, speck diameter) — unrated cafés: invisible zoomed out, a
    /// faint 2pt fleck at neighborhood zoom, 3pt at street. Never larger.
    private static let speckStops: [(span: Double, diameter: CGFloat)] = [
        (0.045, 0), (0.022, 2), (0.011, 3),
    ]
    /// A teardrop shape needs enough pixels for the round head PLUS the
    /// pointed tail to read as a pin rather than a blob — below this the
    /// design intentionally "degrades to a plain dot" (spec's own words).
    public static let teardropShapeThreshold: CGFloat = 10
    /// The number never shows below this head diameter, even on a full
    /// (non-demoted) teardrop.
    public static let numberThreshold: CGFloat = 11
    /// Selected marker: fixed size regardless of zoom (bd#212 spec).
    public static let selectedDiameter: CGFloat = 30
    /// A teardrop that loses a screen-space collision shrinks to this
    /// fraction of the diameter it would otherwise have drawn at.
    public static let demotionScale: CGFloat = 0.42

    /// Piecewise-linear interpolation over `sizeStops`/`speckStops`,
    /// clamped at both ends — smaller span (more zoomed in) always yields a
    /// diameter >= a larger span's, by construction of the stop tables.
    private static func interpolate(_ stops: [(span: Double, diameter: CGFloat)], span: Double) -> CGFloat {
        guard let first = stops.first, let last = stops.last else { return 0 }
        if span >= first.span { return first.diameter }
        if span <= last.span { return last.diameter }
        for i in 0..<(stops.count - 1) {
            let hi = stops[i]
            let lo = stops[i + 1]
            guard span <= hi.span, span >= lo.span else { continue }
            let t = (hi.span - span) / (hi.span - lo.span)
            return hi.diameter + (lo.diameter - hi.diameter) * CGFloat(t)
        }
        return last.diameter
    }

    /// Head diameter (points) for a RATED venue's marker at this
    /// visible-region longitude span, before any collision demotion.
    public static func headDiameter(forLongitudeSpan span: Double) -> CGFloat {
        interpolate(sizeStops, span: span)
    }

    /// Diameter (points) for an UNRATED venue's speck at this span; `0`
    /// means "don't draw it at all" (zoomed all the way out).
    public static func speckDiameter(forLongitudeSpan span: Double) -> CGFloat {
        interpolate(speckStops, span: span)
    }

    // MARK: - Plan

    /// - Parameters:
    ///   - mapSize: the map view's current size in points.
    ///   - selectedVenueID: always rendered as the fixed 30pt selected
    ///     teardrop, seeded into the collision grid first so nothing may
    ///     ever be placed on top of it.
    ///   - exclusionRects: screen-space rects already "occupied" before any
    ///     marker is placed (bd#210, kept unchanged for bd#212) — the
    ///     search header, "Search this area" pill, locate button, shelf
    ///     card. A candidate whose footprint reaches into one goes through
    ///     the SAME demote/drop handling as a marker-vs-marker collision.
    /// - Parameter region: the current camera viewport, or `nil` when it has
    ///   never been observed. A stale/unknown region must never render as an
    ///   empty plan while `venues` is non-empty (brewdesk#157) — falls back
    ///   to the un-culled venue list, every one a full (un-demoted, un-sized)
    ///   teardrop at the "closest" diameter, rather than trusting pixel math
    ///   against a region already known to be wrong.
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
                    kind: .teardrop(diameter: sizeStops.last!.diameter),
                    showsNumber: $0.isObserved,
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
        let grid = CollisionGrid()
        for rect in exclusionRects {
            grid.insert(AABB(minX: rect.minX, maxX: rect.maxX, minY: rect.minY, maxY: rect.maxY))
        }

        let ratedDiameter = headDiameter(forLongitudeSpan: region.span.longitudeDelta)
        let speckSize = speckDiameter(forLongitudeSpan: region.span.longitudeDelta)

        var placed: [MarkerPlacement] = []
        var totalPlaced = 0

        // 1. Selected venue — highest priority, always a full teardrop at
        // the fixed 30pt size, seeded before anything else.
        var selectedVenue: Venue?
        if let selectedVenueID, let match = visible.first(where: { $0.id == selectedVenueID }) {
            let box = footprint(diameter: selectedDiameter, at: projector.point(for: coordinate(of: match)))
            grid.insert(box)
            placed.append(
                MarkerPlacement(
                    venue: match,
                    kind: .teardrop(diameter: selectedDiameter),
                    showsNumber: match.isObserved,
                    isSelected: true
                )
            )
            totalPlaced += 1
            selectedVenue = match
        }

        // 2. Rated (observed) venues, best score first — every one competes
        // for a full teardrop; a screen-space collision demotes it to a
        // small dot instead of dropping it outright (bd#212's overlap
        // rule). Only a demoted dot that STILL collides (an extremely dense
        // pocket) is ever silently skipped.
        let rated = visible
            .filter { $0.isObserved && $0.id != selectedVenue?.id }
            .sorted(by: byScoreDescendingThenID)
        for candidate in rated {
            guard totalPlaced < maxAnnotations else { break }
            let point = projector.point(for: coordinate(of: candidate))
            let teardropBox = footprint(diameter: ratedDiameter, at: point)
            if !grid.collides(teardropBox) {
                grid.insert(teardropBox)
                let showsNumber = ratedDiameter >= numberThreshold
                let kind: MarkerKind = ratedDiameter >= teardropShapeThreshold
                    ? .teardrop(diameter: ratedDiameter)
                    : .dot(diameter: ratedDiameter)
                placed.append(MarkerPlacement(venue: candidate, kind: kind, showsNumber: showsNumber))
                totalPlaced += 1
                continue
            }
            let demotedDiameter = ratedDiameter * demotionScale
            let dotBox = footprint(diameter: demotedDiameter, at: point)
            if !grid.collides(dotBox) {
                grid.insert(dotBox)
                placed.append(MarkerPlacement(venue: candidate, kind: .dot(diameter: demotedDiameter), showsNumber: false))
                totalPlaced += 1
            }
            // Neither the full teardrop nor the demoted dot has room: this
            // venue is dropped for this plan — the hard "no two markers
            // overlap, ever" rule wins over "every venue must render."
        }

        // 3. Unrated (unobserved) venues — faint neutral specks, nearest-
        // to-centre first, never numbered, never tier-colored. `speckSize`
        // is 0 at the widest zoom, which already renders nothing (the
        // `guard speckSize > 0` below just makes that explicit and skips
        // the collision work entirely at that zoom).
        if speckSize > 0 {
            let unratedEligible = visible.filter { !$0.isObserved && $0.id != selectedVenue?.id }
            let nearest = nearestToCentre(unratedEligible, region: region, limit: unratedCandidateLimit)
            for candidate in nearest {
                guard totalPlaced < maxAnnotations else { break }
                let point = projector.point(for: coordinate(of: candidate))
                let box = footprint(diameter: speckSize, at: point)
                guard !grid.collides(box) else { continue }
                grid.insert(box)
                placed.append(MarkerPlacement(venue: candidate, kind: .speck(diameter: speckSize), showsNumber: false))
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

    /// The footprint a marker of this diameter occupies for collision
    /// purposes — a touch taller than wide to account for a teardrop's
    /// pointed tail (a dot/speck's true footprint is smaller than this, but
    /// treating every kind the same, conservative way keeps demotion from
    /// ever re-colliding with what it just avoided).
    static func footprint(diameter: CGFloat, at point: CGPoint) -> AABB {
        let pad = footprintPadding * 2
        let width = diameter + pad
        let height = diameter * tailHeightFactor + pad
        return AABB(
            minX: point.x - width / 2, maxX: point.x + width / 2,
            minY: point.y - height / 2, maxY: point.y + height / 2
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

/// Axis-aligned bounding box used as every marker's collision footprint.
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
