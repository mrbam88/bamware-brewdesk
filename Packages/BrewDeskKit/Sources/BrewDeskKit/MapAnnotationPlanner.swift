import CoreGraphics
import MapKit
import VenueKit

/// One grid-cell's worth of venues collapsed into a single map annotation.
public struct VenueCluster: Identifiable, Hashable, Sendable {
    /// Stable per zoom level: grid indices + the quantized cell exponent, so
    /// panning at an unchanged zoom keeps cluster identity (no churn). A
    /// subdivided cell (bd#204) carries the FINER exponent in its id, so it
    /// never collides with its unsplit parent's id. A stack synthesized from
    /// "homeless" dots that collided their way into a group (bd#209) carries
    /// a `homeless-` prefixed id instead — see `MapAnnotationPlanner.plan`.
    public let id: String
    public let latitude: Double
    public let longitude: Double
    public let count: Int
    /// Highest Work Fit among the cell's OBSERVED venues (bd#159) — a
    /// venue with no real evidence never sets this, so a cell of entirely
    /// unobserved venues can't paint itself with a fabricated tier color.
    /// Meaningless when `hasObservedVenue` is false; callers must check
    /// that first.
    public let bestScore: Int
    /// True when at least one venue in the cell is observed. Drives whether
    /// the cluster pill tints by `bestScore` or renders the neutral
    /// "not checked yet" treatment (bd#159).
    public let hasObservedVenue: Bool

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// What the map should draw for the current venues + camera (brewdesk#54,
/// re-shaped bd#204, made collision-free bd#209). Representation only — no
/// styling. Views decide what a pin/dot/cluster looks like
/// (`MapAnnotationViews`) without touching this logic.
public struct MapAnnotationPlan: Equatable {
    /// Full score pins — the top-ranked OBSERVED venues in view (bd#204),
    /// filtered through the bd#209 screen-space collision pass: a candidate
    /// that would overlap an already-placed marker is demoted to a dot
    /// instead, so this is no longer guaranteed to be exactly `pinLimit`
    /// long even in a dense viewport.
    public let pins: [Venue]
    /// Score-tier dots for what's left after `pins` — also collision-
    /// filtered: a dot that would overlap something is absorbed into a
    /// nearby stack, folded into a brand-new one alongside its neighbours,
    /// or dropped, never drawn on top of another marker (bd#209).
    public let dots: [Venue]
    /// Grid clusters ("stacks") for whatever overflows `pins` + `dots`,
    /// positioned at their member venues' own centroid (never a raw grid
    /// cell centre — bd#209) and nudged through the same collision pass.
    public let clusters: [VenueCluster]

    public init(pins: [Venue], dots: [Venue], clusters: [VenueCluster]) {
        self.pins = pins
        self.dots = dots
        self.clusters = clusters
    }

    public var annotationCount: Int { pins.count + dots.count + clusters.count }

    /// Whether this plan already renders the venue as an individual annotation
    /// (the screen adds a selected-pin overlay only when it does not).
    public func containsVenue(id: String) -> Bool {
        pins.contains { $0.id == id } || dots.contains { $0.id == id }
    }
}

/// Pure, unit-tested planning: viewport culling with a margin, then a
/// collision-free screen-space layout (bd#209). Never called mid-gesture —
/// the map screen re-plans only when a camera move ends.
public enum MapAnnotationPlanner {
    /// At or below this many visible venues, every one gets a shot at a full
    /// pin — AND, above it, this is also the number of top-ranked OBSERVED
    /// venues that always compete for a pin slot regardless of density
    /// (bd#204): the West Village screenshot bug was café evidence
    /// disappearing into a cluster count; the best-evidenced venues in view
    /// must never do that. bd#209: "compete for" rather than "always get" —
    /// a candidate that collides with a higher-priority marker already on
    /// screen is demoted to a dot instead (see `plan`).
    public static let pinLimit = 25
    /// How many left-over venues (after `pinLimit`) are even considered as
    /// dot candidates, nearest-to-centre first, before the collision pass
    /// and the `maxAnnotations` cap take over. `pinLimit` (25) plus this
    /// can never actually all render — `maxAnnotations` (120) always wins —
    /// so this is kept close to that real ceiling rather than far above it:
    /// a bigger number only means more wasted collision/absorption work on
    /// candidates the cap was always going to drop.
    public static let dotCandidateLimit = 100
    /// Hard ceiling on total rendered annotations (25 pins + stacks + dots,
    /// bd#209) — the direct fix for the perf regression #208 introduced by
    /// drawing pins+dots+clusters simultaneously with no shared cap
    /// (hitchRatio 0.16–0.19 measured against a 0.20 bound). Every phase in
    /// `plan` stops adding markers once this is hit; whatever's left is
    /// absorbed into an existing stack or dropped, never rendered past it.
    public static let maxAnnotations = 120
    /// Extra region kept annotated on every side (fraction of the span), so
    /// a pan shorter than half a screen never uncovers un-annotated map.
    public static let cullMargin = 0.5
    /// Cluster grid targets about this many cells across the viewport.
    public static let targetCellsAcross = 1.5
    /// Cluster-grid span used only when the camera region is genuinely
    /// unknown (brewdesk#157) — kept for `clusterCellDegrees`'s own tests;
    /// `plan()` itself skips clustering entirely on an unknown region (see
    /// below).
    public static let fallbackSpanLongitude = 0.035
    /// Map-view size used for screen-space collision math when the real
    /// `mapSize` hasn't been measured yet (the very first `plan()` call, one
    /// frame before `CafeMapScreen`'s `GeometryReader` reports a real size).
    /// An ordinary phone-portrait map viewport — good enough for one frame;
    /// the next replan uses the real size.
    public static let fallbackMapSize = CGSize(width: 390, height: 660)

    // MARK: - bd#209 marker footprints (screen points)

    /// Shared margin added around every marker's own visual size before two
    /// footprints are tested for overlap — the padding IS the minimum gap
    /// between two markers, not just breathing room inside one.
    public static let footprintPadding: CGFloat = 4

    enum MarkerKind: Equatable {
        case pin, stack, dot

        /// Visual size, before `footprintPadding`.
        var size: CGSize {
            switch self {
            case .pin: CGSize(width: 44, height: 44)
            case .stack: CGSize(width: 52, height: 40)
            case .dot: CGSize(width: 12, height: 12)
            }
        }

        /// The actual collision footprint: visual size plus the shared
        /// padding margin on every side.
        var paddedSize: CGSize {
            let pad = MapAnnotationPlanner.footprintPadding * 2
            return CGSize(width: size.width + pad, height: size.height + pad)
        }
    }

    /// How far (screen points) a dot may reach to fold into an existing
    /// stack rather than starting a new "homeless" group of its own — about
    /// twice a stack footprint's diagonal, so absorption only ever pulls in
    /// a venue that's genuinely near that stack, never one from across the
    /// screen.
    private static let stackAbsorptionRadius: CGFloat = 160

    /// - Parameters:
    ///   - mapSize: the map view's current size in points. Needed to turn a
    ///     coordinate into a screen point for collision math; falls back to
    ///     `fallbackMapSize` when not yet measured (`.zero`/default).
    ///   - selectedVenueID: the currently-selected venue, if any. Placed
    ///     first and unconditionally as a full pin — nothing else may ever
    ///     cover it — matching `CafeMapScreen`'s existing "selected pin
    ///     always visible" contract. Not checked against `exclusionRects`
    ///     (out of scope — see bd#210's PR notes).
    ///   - exclusionRects: screen-space rects (same coordinate space as
    ///     `mapSize` — the map view's own local frame) that are already
    ///     "occupied" before any marker is placed (bd#210) — fixed app
    ///     chrome (the search header, the "Search this area" pill, the
    ///     locate button, the shelf card) that would otherwise sit on top of
    ///     a marker drawn at its real coordinate. Seeded into the collision
    ///     grid first, so every later phase's normal collision handling
    ///     (pin → demote to dot, stack → nudge/merge, dot → absorb/homeless/
    ///     drop) already covers them with no separate code path.
    /// - Parameter region: the current camera viewport, or `nil` when it has
    ///   never been observed (cold start before the first camera settle) or a
    ///   `MapProxy` conversion failed. Either way this must never render as
    ///   an empty plan while `venues` is non-empty (brewdesk#157) — a stale
    ///   or unknown region falls back to the un-culled venue list instead of
    ///   silently hiding every pin. Precise pixel collision math needs a
    ///   region worth trusting, so bd#209's collision pass is skipped
    ///   entirely on this rescue path (every venue renders as a plain pin,
    ///   same as before bd#209) rather than laid out against a region
    ///   already known to be wrong.
    /// - Parameter previousPlan: the last plan actually rendered, if any
    ///   (bd#211 incremental-placement hysteresis). When supplied, a venue
    ///   that was ALREADY a pin (or already a dot) last time is given first
    ///   crack at keeping that exact footprint this time, ahead of other
    ///   equally-eligible candidates — see the collision-priority reordering
    ///   at each phase below. Profiling (#211) found the re-plan itself
    ///   cheap (worst call ~40ms) but nearly the whole annotation set losing
    ///   and regaining its identity on every settle — not because those
    ///   venues left the viewport, but because a fresh score/distance sort
    ///   reshuffles which of several EQUALLY eligible venues wins a slot
    ///   purely from candidates entering/leaving elsewhere in view.
    ///
    ///   This deliberately does NOT change who is ELIGIBLE for a pin or dot
    ///   slot — a first cut that let a previously-placed venue keep its kind
    ///   outright (skipping the top-`pinLimit`/nearest-`dotCandidateLimit`
    ///   gates entirely) broke `testClustersZoomToVenuesAndDetailTapThrough`
    ///   in the app suite: early low-count plans during initial load had
    ///   room for individual markers, and hysteresis kept "locking in" that
    ///   representation as more venues streamed in, so the city-wide view
    ///   never fell back to clusters. Reordering PRIORITY within the exact
    ///   same eligible-candidate set can't change which representation a
    ///   dense viewport ultimately settles into, only which of several
    ///   equally-ranked candidates wins a contested footprint — so the
    ///   "visible result must not change" requirement holds by construction,
    ///   not by re-testing every case. `nil` (the default) reproduces the
    ///   exact pre-#211 behaviour — every existing call site and test that
    ///   never passes this is unaffected.
    public static func plan(
        venues: [Venue],
        region: MKCoordinateRegion?,
        mapSize: CGSize = .zero,
        selectedVenueID: String? = nil,
        exclusionRects: [CGRect] = [],
        previousPlan: MapAnnotationPlan? = nil
    ) -> MapAnnotationPlan {
        guard let region else {
            return MapAnnotationPlan(pins: venues, dots: [], clusters: [])
        }
        let culledVenues = culled(venues, region: region)
        let visible = (culledVenues.isEmpty && !venues.isEmpty) ? venues : culledVenues
        guard !visible.isEmpty else {
            return MapAnnotationPlan(pins: [], dots: [], clusters: [])
        }

        let size = (mapSize.width > 0 && mapSize.height > 0) ? mapSize : fallbackMapSize
        let projector = ScreenProjector(region: region, size: size)
        let grid = CollisionGrid()
        // bd#210: chrome occupies its screen space before any marker gets a
        // chance at it — a pin/stack/dot whose footprint reaches into one of
        // these rects is handled by the SAME demote/nudge/absorb machinery a
        // marker-vs-marker collision already goes through below.
        for rect in exclusionRects {
            grid.insert(AABB(minX: rect.minX, maxX: rect.maxX, minY: rect.minY, maxY: rect.maxY))
        }
        var totalPlaced = 0

        var pinsOut: [Venue] = []
        var dotsOut: [Venue] = []
        var placedIDs = Set<String>()

        // 1. Selected venue: highest priority, always a full pin, seeded
        // before anything else so nothing can be placed on top of it.
        var selectedVenue: Venue?
        if let selectedVenueID, let match = visible.first(where: { $0.id == selectedVenueID }) {
            grid.insert(projector.footprint(.pin, at: coordinate(of: match)))
            pinsOut.append(match)
            placedIDs.insert(match.id)
            totalPlaced += 1
            selectedVenue = match
        }

        // 2. Score pins: top `pinLimit` OBSERVED venues by Work Fit
        // (bd#204's rule, unchanged) — unobserved venues never compete for a
        // pin slot. Each candidate is placed if its footprint is still
        // clear; a collision demotes it to a dot candidate instead of
        // dropping it outright (bd#209).
        let pinCandidates = topScoringObserved(
            visible.filter { $0.id != selectedVenue?.id }, limit: pinLimit
        )
        // bd#211: iteration order only — a candidate that was ALSO a pin in
        // `previousPlan` is tried first, so on a collision between two
        // otherwise-tied candidates the one already occupying that screen
        // space keeps it. The ELIGIBLE SET above (`pinCandidates`) is
        // unchanged, so this can never place a venue that wasn't already
        // going to compete for a pin regardless of history.
        let previousPinIDs = Set((previousPlan?.pins ?? []).map(\.id))
        let orderedPinCandidates = previousPinIDs.isEmpty ? pinCandidates : pinCandidates.sorted { lhs, rhs in
            let lhsCarried = previousPinIDs.contains(lhs.id)
            let rhsCarried = previousPinIDs.contains(rhs.id)
            return lhsCarried && !rhsCarried
        }
        var demotedToDots: [Venue] = []
        for candidate in orderedPinCandidates {
            guard totalPlaced < maxAnnotations else {
                demotedToDots.append(candidate)
                continue
            }
            let box = projector.footprint(.pin, at: coordinate(of: candidate))
            if grid.collides(box) {
                demotedToDots.append(candidate)
            } else {
                grid.insert(box)
                pinsOut.append(candidate)
                placedIDs.insert(candidate.id)
                totalPlaced += 1
            }
        }
        let pinCandidateIDs = Set(pinCandidates.map(\.id))

        // 3. Dot candidates: nearest-to-centre of what's left (bd#204's
        // existing rule), capped at `dotCandidateLimit` before collision
        // even runs.
        let dotEligible = visible.filter { !placedIDs.contains($0.id) && !pinCandidateIDs.contains($0.id) }
        let nearestDotCandidates = nearestToCentre(dotEligible, region: region, limit: dotCandidateLimit)
        let dotCandidateIDs = Set(nearestDotCandidates.map(\.id)).union(demotedToDots.map(\.id))

        // 4. Stacks: grid-cluster whatever's left in the WHOLE dataset (not
        // just `visible`) minus everything already claimed above — the grid
        // itself stays absolute across pans at an unchanged zoom
        // (brewdesk#54's zero-churn guarantee); only membership shifts with
        // the viewport. Each cluster is placed at ITS MEMBERS' OWN centroid,
        // never a raw grid cell centre (bd#209 — the #208 bug where a stack
        // could land over the Hudson because its cell happened to straddle
        // the shoreline). A collision nudges the stack outward through a
        // deterministic search; if that still can't find room it merges
        // into the nearest already-placed stack instead of ever drawing on
        // top of one.
        let clusterable = venues.filter {
            !placedIDs.contains($0.id) && !pinCandidateIDs.contains($0.id) && !dotCandidateIDs.contains($0.id)
        }
        let stackCandidates = clusters(for: clusterable, spanLongitude: region.span.longitudeDelta)
        var placedStacks: [StackState] = []
        for candidate in stackCandidates {
            guard totalPlaced < maxAnnotations else { break }
            let before = placedStacks.count
            place(stackCandidate: candidate, projector: projector, grid: grid, placedStacks: &placedStacks)
            if placedStacks.count > before { totalPlaced += 1 }
        }

        // 5. Dots: demoted score pins first (higher-value venues that only
        // lost their pin slot to crowding), then the nearest-to-centre pool,
        // both in a deterministic order. A collision tries absorption into a
        // nearby stack; failing that, venues pile into a "homeless" bucket
        // keyed by screen cell, and three or more in the same cell become a
        // brand-new stack of their own. Anything left under three when the
        // pass ends is simply never drawn — a deliberate drop, not a bug
        // (bd#209 spec: "absorbed into the nearest stack … or dropped").
        var homeless: [ScreenCellKey: [Venue]] = [:]
        let baseDotAttempts = demotedToDots.sorted(by: byScoreDescendingThenID) + nearestDotCandidates
        // bd#211: same iteration-order-only priority as the pin phase above
        // — a candidate that was ALSO a dot in `previousPlan` is tried
        // first within this UNCHANGED candidate set.
        let previousDotIDs = Set((previousPlan?.dots ?? []).map(\.id))
        let orderedDotAttempts = previousDotIDs.isEmpty ? baseDotAttempts : baseDotAttempts.sorted { lhs, rhs in
            let lhsCarried = previousDotIDs.contains(lhs.id)
            let rhsCarried = previousDotIDs.contains(rhs.id)
            return lhsCarried && !rhsCarried
        }
        for candidate in orderedDotAttempts {
            guard totalPlaced < maxAnnotations else { break }
            let point = projector.point(for: coordinate(of: candidate))
            let box = projector.footprint(.dot, at: point)
            if !grid.collides(box) {
                grid.insert(box)
                dotsOut.append(candidate)
                totalPlaced += 1
                continue
            }
            if let nearest = nearestStack(to: point, in: placedStacks, within: stackAbsorptionRadius) {
                nearest.absorb(candidate)
                continue
            }
            let key = ScreenCellKey(point: point, cellSize: MarkerKind.stack.paddedSize.width)
            homeless[key, default: []].append(candidate)
            if homeless[key]!.count >= 3, totalPlaced < maxAnnotations {
                let members = homeless.removeValue(forKey: key)!
                // bd#211: id from the MEMBER SET, not the screen-space bucket
                // key — `key.cx/cy` shift on every pan even when the exact
                // same venues fall homeless again, which handed SwiftUI a
                // brand-new annotation identity (and forced MapKit to tear
                // down and rebuild the stack's view) on nearly every settle.
                // A sorted, joined member-id string is deterministic for the
                // same membership regardless of where it lands on screen.
                let synthesized = aggregate(members, id: "homeless-\(homelessMemberKey(members))")
                let before = placedStacks.count
                place(stackCandidate: synthesized, projector: projector, grid: grid, placedStacks: &placedStacks)
                if placedStacks.count > before { totalPlaced += 1 }
            }
        }

        let clustersOut = placedStacks.map(\.asVenueCluster).sorted { $0.id < $1.id }
        return MapAnnotationPlan(pins: pinsOut, dots: dotsOut, clusters: clustersOut)
    }

    /// Deterministic key for a "homeless" stack's identity (bd#211): sorted
    /// member venue ids joined, so the id depends only on WHICH venues
    /// grouped together, never on where the group happened to land on
    /// screen this particular `plan()` call.
    private static func homelessMemberKey(_ members: [Venue]) -> String {
        members.map(\.id).sorted().joined(separator: ",")
    }

    private static func coordinate(of venue: Venue) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: venue.lat, longitude: venue.lng)
    }

    private static func byScoreDescendingThenID(_ lhs: Venue, _ rhs: Venue) -> Bool {
        lhs.workScore != rhs.workScore ? lhs.workScore > rhs.workScore : lhs.id < rhs.id
    }

    /// The venues to draw individually before the pin/dot/cluster threshold
    /// applies. Un-culled whenever the region is unknown, and un-culled
    /// whenever a KNOWN region culls every venue away while venues actually
    /// exist — that second case is a stale or mismatched `visibleRegion`
    /// (search cleared, filter changed, camera moved with no gesture), not a
    /// genuinely empty viewport, and brewdesk#157 is exactly that the map
    /// must never go pinless while the header count is non-zero.
    static func candidates(venues: [Venue], region: MKCoordinateRegion?) -> [Venue] {
        guard let region else { return venues }
        let culledVenues = culled(venues, region: region)
        return (culledVenues.isEmpty && !venues.isEmpty) ? venues : culledVenues
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

    /// Cell edge in degrees for a given zoom, quantized to a power of two so
    /// panning at the same zoom never re-buckets venues into different cells.
    public static func clusterCellDegrees(spanLongitude: Double) -> Double {
        let target = max(spanLongitude, 0.0005) / targetCellsAcross
        return pow(2, log2(target).rounded())
    }

    /// Fixed-grid clustering: venue → cell by coordinate, cluster at the
    /// cell's centroid. Deterministic output order (by id). This centroid is
    /// the PRE-SNAP position `plan()` hands to its collision pass — never the
    /// rendered position on its own (bd#209; see `place(stackCandidate:…)`).
    public static func clusters(for venues: [Venue], spanLongitude: Double) -> [VenueCluster] {
        let cell = clusterCellDegrees(spanLongitude: spanLongitude)
        var buckets: [String: (latSum: Double, lngSum: Double, count: Int, bestScore: Int, hasObserved: Bool)] = [:]
        for venue in venues {
            let key = cellKey(lat: venue.lat, lng: venue.lng, cellDegrees: cell)
            var bucket = buckets[key] ?? (0, 0, 0, 0, false)
            bucket.latSum += venue.lat
            bucket.lngSum += venue.lng
            bucket.count += 1
            // Unobserved venues never vote for `bestScore` (bd#159) — a
            // cell can't paint itself with a fabricated tier color.
            if venue.isObserved {
                bucket.bestScore = bucket.hasObserved ? max(bucket.bestScore, venue.workScore) : venue.workScore
                bucket.hasObserved = true
            }
            buckets[key] = bucket
        }
        return buckets
            .map { key, bucket in
                VenueCluster(
                    id: key,
                    latitude: bucket.latSum / Double(bucket.count),
                    longitude: bucket.lngSum / Double(bucket.count),
                    count: bucket.count,
                    bestScore: bucket.bestScore,
                    hasObservedVenue: bucket.hasObserved
                )
            }
            .sorted { $0.id < $1.id }
    }

    // MARK: - bd#204 helpers

    /// Grid-cell key for one coordinate at a given cell size.
    private static func cellKey(lat: Double, lng: Double, cellDegrees: Double) -> String {
        let latIndex = Int((lat / cellDegrees).rounded(.down))
        let lngIndex = Int((lng / cellDegrees).rounded(.down))
        return "cluster-\(latIndex)-\(lngIndex)-\(Int(log2(cellDegrees).rounded()))"
    }

    /// Top `limit` OBSERVED venues by Work Fit, ties broken by id for
    /// deterministic output.
    private static func topScoringObserved(_ venues: [Venue], limit: Int) -> [Venue] {
        Array(venues.filter(\.isObserved).sorted(by: byScoreDescendingThenID).prefix(limit))
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

    private static func aggregate(_ members: [Venue], id: String) -> VenueCluster {
        var latSum = 0.0
        var lngSum = 0.0
        var bestScore = 0
        var hasObserved = false
        for venue in members {
            latSum += venue.lat
            lngSum += venue.lng
            if venue.isObserved {
                bestScore = hasObserved ? max(bestScore, venue.workScore) : venue.workScore
                hasObserved = true
            }
        }
        return VenueCluster(
            id: id,
            latitude: latSum / Double(members.count),
            longitude: lngSum / Double(members.count),
            count: members.count,
            bestScore: bestScore,
            hasObservedVenue: hasObserved
        )
    }

    // MARK: - bd#209: screen-space collision layout

    /// Places one stack candidate (from `clusters(for:)`/`aggregate`): its
    /// exact centroid first, then a deterministic outward search on
    /// collision, then — only if no free spot exists nearby — merged into
    /// the nearest already-placed stack rather than lost. `renderedCoordinate`
    /// is set exactly once and never moves again (later dot absorption in
    /// `plan()` changes only `count`/`bestScore`), so a stack always stays
    /// within one footprint of the centroid it was actually placed at.
    private static func place(
        stackCandidate candidate: VenueCluster,
        projector: ScreenProjector,
        grid: CollisionGrid,
        placedStacks: inout [StackState]
    ) {
        let desired = projector.point(for: candidate.coordinate)
        if let point = freePoint(near: desired, kind: .stack, projector: projector, grid: grid) {
            grid.insert(projector.footprint(.stack, at: point))
            placedStacks.append(
                StackState(
                    id: candidate.id,
                    renderedCoordinate: projector.coordinate(for: point),
                    point: point,
                    count: candidate.count,
                    bestScore: candidate.bestScore,
                    hasObserved: candidate.hasObservedVenue
                )
            )
            return
        }
        if let nearest = nearestStack(to: desired, in: placedStacks, within: stackAbsorptionRadius) {
            nearest.absorb(count: candidate.count, bestScore: candidate.bestScore, hasObserved: candidate.hasObservedVenue)
            return
        }
        // Nowhere to put it and nothing nearby to fold into — an extremely
        // dense pathological case only. The venues it represented stay
        // uncounted by any single marker rather than being drawn on top of
        // one (bd#209's "no two markers overlap, ever" is the hard rule).
    }

    /// Exact centroid first; on collision, a deterministic ring search
    /// outward (never random — `plan()` must stay reproducible for the same
    /// input) at increasing multiples of the marker's own footprint, 8
    /// compass directions per ring, 3 rings. `nil` means every position
    /// tried also collided.
    /// bd#210: a candidate must stay fully within the map's own visible
    /// bounds, not just be collision-free — without this, a stack fleeing
    /// an exclusion rect near an edge (the search header at the top, the
    /// shelf at the bottom) could get nudged clean off the map: still
    /// "placed" and present in the accessibility tree, but not actually
    /// visible or tappable (reproduced by `MapPerformanceUITests
    /// .testScriptedPanFrameTimingAtDotZoom`'s "no hittable cluster pill"
    /// failure). A candidate that fails this is treated exactly like a
    /// collision — the ring search keeps looking, and running out falls
    /// through to the existing merge-into-nearest-stack/drop fallback.
    private static func freePoint(
        near desired: CGPoint, kind: MarkerKind, projector: ScreenProjector, grid: CollisionGrid
    ) -> CGPoint? {
        func isValid(_ point: CGPoint) -> Bool {
            let box = projector.footprint(kind, at: point)
            guard box.minX >= 0, box.maxX <= projector.size.width,
                  box.minY >= 0, box.maxY <= projector.size.height
            else { return false }
            return !grid.collides(box)
        }
        if isValid(desired) { return desired }
        let step = max(kind.paddedSize.width, kind.paddedSize.height)
        let directions: [(CGFloat, CGFloat)] = [
            (1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1),
        ]
        for ring in 1...3 {
            for (dx, dy) in directions {
                let candidate = CGPoint(
                    x: desired.x + dx * step * CGFloat(ring),
                    y: desired.y + dy * step * CGFloat(ring)
                )
                if isValid(candidate) { return candidate }
            }
        }
        return nil
    }

    private static func nearestStack(to point: CGPoint, in stacks: [StackState], within radius: CGFloat) -> StackState? {
        var best: StackState?
        var bestDistance = radius
        for stack in stacks {
            let dx = stack.point.x - point.x
            let dy = stack.point.y - point.y
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance <= bestDistance {
                bestDistance = distance
                best = stack
            }
        }
        return best
    }
}

// MARK: - bd#209: screen projection, collision grid, mutable placement state

/// Linear (equirectangular) mapping between a `MKCoordinateRegion` and a
/// view's point space — accurate enough at city scale (the ticket's own
/// call), and consistent with how `CafeMapScreen` already derives `region`
/// itself, by converting the SAME view's screen corners through `MapProxy`.
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

    func coordinate(for point: CGPoint) -> CLLocationCoordinate2D {
        let lng = minLng + (Double(point.x) / Double(size.width)) * lngSpan
        let lat = minLat + (1 - Double(point.y) / Double(size.height)) * latSpan
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    func footprint(_ kind: MapAnnotationPlanner.MarkerKind, at coordinate: CLLocationCoordinate2D) -> AABB {
        footprint(kind, at: point(for: coordinate))
    }

    func footprint(_ kind: MapAnnotationPlanner.MarkerKind, at point: CGPoint) -> AABB {
        let s = kind.paddedSize
        return AABB(
            minX: point.x - s.width / 2, maxX: point.x + s.width / 2,
            minY: point.y - s.height / 2, maxY: point.y + s.height / 2
        )
    }
}

/// Axis-aligned bounding box used as every marker's collision footprint.
/// Testing box-vs-box rather than the true circle/rounded-rect shape is
/// deliberately conservative — it can reject a placement two shapes would
/// have just cleared, never the reverse — so "no box intersection" is a
/// sufficient, simple guarantee that the drawn shapes never overlap either.
struct AABB {
    var minX, maxX, minY, maxY: CGFloat

    func intersects(_ other: AABB) -> Bool {
        minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY
    }
}

/// Uniform grid spatial hash over already-placed footprints, so a new
/// candidate is checked against only its own neighbourhood instead of every
/// prior marker — `plan()` stays O(n) even at the ticket's 500-venue dense
/// viewport. Cell size (64pt) is picked to comfortably exceed the largest
/// padded footprint (the stack, 60×48pt), so any one box spans at most a
/// handful of cells.
final class CollisionGrid {
    private let cellSize: CGFloat = 64
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

/// Screen cell used only to bucket "homeless" dots (bd#209's ≥3-in-one-cell
/// rule) — deliberately sized to a stack's own footprint, so three dots that
/// collide near enough to have collided with each other are exactly the
/// venues a viewer would expect one new stack to group.
struct ScreenCellKey: Hashable {
    let cx: Int
    let cy: Int

    init(point: CGPoint, cellSize: CGFloat) {
        cx = Int((point.x / cellSize).rounded(.down))
        cy = Int((point.y / cellSize).rounded(.down))
    }
}

/// A stack marker actually placed on screen this `plan()` call. Reference
/// type so dot absorption (`absorb`) can update `count`/`bestScore` in place
/// without threading array indices back through several call sites.
/// `renderedCoordinate`/`point` are set once at placement and never move —
/// absorbing more venues afterward only grows what the marker represents,
/// never its position (bd#209: "never farther than one footprint" from the
/// centroid it was placed at).
final class StackState {
    let id: String
    let renderedCoordinate: CLLocationCoordinate2D
    let point: CGPoint
    private(set) var count: Int
    private(set) var bestScore: Int
    private(set) var hasObserved: Bool

    init(id: String, renderedCoordinate: CLLocationCoordinate2D, point: CGPoint, count: Int, bestScore: Int, hasObserved: Bool) {
        self.id = id
        self.renderedCoordinate = renderedCoordinate
        self.point = point
        self.count = count
        self.bestScore = bestScore
        self.hasObserved = hasObserved
    }

    func absorb(_ venue: Venue) {
        count += 1
        if venue.isObserved {
            bestScore = hasObserved ? max(bestScore, venue.workScore) : venue.workScore
            hasObserved = true
        }
    }

    func absorb(count extraCount: Int, bestScore extraBestScore: Int, hasObserved extraHasObserved: Bool) {
        count += extraCount
        if extraHasObserved {
            bestScore = hasObserved ? max(bestScore, extraBestScore) : extraBestScore
            hasObserved = true
        }
    }

    var asVenueCluster: VenueCluster {
        VenueCluster(
            id: id,
            latitude: renderedCoordinate.latitude,
            longitude: renderedCoordinate.longitude,
            count: count,
            bestScore: bestScore,
            hasObservedVenue: hasObserved
        )
    }
}
