import MapKit
import VenueKit

/// One grid-cell's worth of venues collapsed into a single map annotation.
public struct VenueCluster: Identifiable, Hashable, Sendable {
    /// Stable per zoom level: grid indices + the quantized cell exponent, so
    /// panning at an unchanged zoom keeps cluster identity (no churn). A
    /// subdivided cell (bd#204) carries the FINER exponent in its id, so it
    /// never collides with its unsplit parent's id.
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
/// re-shaped bd#204). No longer a single-representation enum: a dense
/// viewport now shows all three layers AT ONCE — evidence-backed venues stay
/// visible as pins even when the rest of the viewport is dense enough to
/// need dots or clusters underneath them. Representation only — no styling.
/// Views decide what a pin/dot/cluster looks like (`MapAnnotationViews`)
/// without touching this logic.
public struct MapAnnotationPlan: Equatable {
    /// Full score pins — always the top-ranked OBSERVED venues in view
    /// (bd#204), however dense the viewport. Never swallowed by a cluster.
    public let pins: [Venue]
    /// Score-tier dots for what's left after `pins`, up to `dotBudget`.
    public let dots: [Venue]
    /// Grid clusters for whatever overflows `pins` + `dots`.
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
/// zoom/density-dependent representation. Never called mid-gesture — the map
/// screen re-plans only when a camera move ends.
public enum MapAnnotationPlanner {
    /// At or below this many visible venues, every one gets a full pin —
    /// AND, above it, this is also the number of top-ranked OBSERVED venues
    /// that always render as full pins regardless of density (bd#204): the
    /// West Village screenshot bug was café evidence disappearing into a
    /// cluster count; the best-evidenced venues in view must never do that.
    public static let pinLimit = 25
    /// Dot mode renders at most this many dots — the best-ranked-by-distance
    /// visible venues left after `pinLimit` (nearest-to-centre, bd#204).
    /// bd#204's issue draft floated raising this toward ~250 now that a
    /// viewport can hold up to 500 venues, but measuring against
    /// `MapPerformanceUITests` on-simulator showed that pins+dots+clusters
    /// now draw SIMULTANEOUSLY (unlike the old mutually-exclusive
    /// pins-OR-dots-OR-clusters design), so raising this compounds with
    /// `pinLimit` and cluster count rather than replacing them — 180 dots
    /// measured hitchRatio 0.36 (vs. the ≤0.20 regression bound), 60
    /// measured 0.20 (borderline). Left at its original brewdesk#54 value:
    /// the always-visible top-25 pins (never present before bd#204) and the
    /// `maxClusterShare` guard below already fix the reported bug — evidence
    /// no longer disappears into a cluster, and no single bubble can dominate
    /// the viewport — without needing the raw dot count to grow. See the
    /// bd#204 PR for the full measurement table.
    public static let dotBudget = 40
    /// Extra region kept annotated on every side (fraction of the span), so
    /// a pan shorter than half a screen never uncovers un-annotated map.
    public static let cullMargin = 0.5
    /// Cluster grid targets about this many cells across the viewport.
    /// bd#204 tried raising this (to 2.0, then 5.0) to shrink individual
    /// cluster cells directly, but a finer BASE grid multiplies the total
    /// cluster-pill count across the whole dataset (not just the crowded
    /// cells that actually need splitting) — measured hitchRatio 0.14–0.20
    /// at 2.0–2.5 vs. 0.12 at the original 1.5. Left unchanged: the
    /// `maxClusterShare` guard below is a DENSITY-AWARE backstop that only
    /// subdivides the specific cell that's actually too big (bd#204's "one
    /// bubble held 125 of 265 cafés"), so it fixes the reported bug without
    /// this grid needing to get finer everywhere.
    public static let targetCellsAcross = 1.5
    /// Cluster-grid span used only when the camera region is genuinely
    /// unknown (brewdesk#157) — the same span the map screen's initial
    /// camera opens with, so a cold-start plan groups venues the same way
    /// the first real region would.
    public static let fallbackSpanLongitude = 0.035
    /// A single cluster may never hold more than this share of the visible
    /// venues (bd#204) — the direct fix for "one bubble had 125 of the 265
    /// cafés in view." A cell over the line is subdivided once at half the
    /// grid's cell size; if that still doesn't split it (e.g. every venue
    /// sits at literally the same coordinate) the oversized cluster is kept
    /// rather than looping.
    public static let maxClusterShare = 0.4

    /// - Parameter region: the current camera viewport, or `nil` when it has
    ///   never been observed (cold start before the first camera settle) or a
    ///   `MapProxy` conversion failed. Either way this must never render as
    ///   an empty plan while `venues` is non-empty (brewdesk#157) — a stale
    ///   or unknown region falls back to the un-culled venue list instead of
    ///   silently hiding every pin.
    public static func plan(venues: [Venue], region: MKCoordinateRegion?) -> MapAnnotationPlan {
        let visible = candidates(venues: venues, region: region)

        // Few enough to pin every one of them — no dots/clusters needed.
        if visible.count <= pinLimit {
            return MapAnnotationPlan(pins: visible, dots: [], clusters: [])
        }

        // Always-visible score pins (bd#204): the top `pinLimit` OBSERVED
        // venues in view by Work Fit, never swallowed by a cluster however
        // dense the rest of the viewport. Unobserved venues never compete
        // for a pin slot here — same bd#159 rule as everywhere else: no
        // fabricated-score venue gets promoted over real evidence.
        let topPins = topScoringObserved(visible, limit: pinLimit)
        let topPinIDs = Set(topPins.map(\.id))
        let remainingVisible = visible.filter { !topPinIDs.contains($0.id) }

        // Everything left fits as dots — no clustering needed.
        if remainingVisible.count <= dotBudget {
            return MapAnnotationPlan(pins: topPins, dots: remainingVisible, clusters: [])
        }

        // Dots: the nearest-to-centre of what's left, up to the budget —
        // prioritizing what's actually in the middle of the screen over
        // whatever the model's own rank order would have kept (bd#204).
        let dots = nearestToCentre(remainingVisible, region: region, limit: dotBudget)
        let dotIDs = Set(dots.map(\.id))
        let overflowIDs = topPinIDs.union(dotIDs)

        // Cluster the WHOLE dataset minus what's already individually
        // rendered — the grid itself stays absolute across pans at an
        // unchanged zoom (brewdesk#54's zero-churn guarantee); only cell
        // MEMBERSHIP can shift as which venues are promoted to pins/dots
        // changes with the viewport, and that only ever happens at a
        // replan (camera settle), never mid-gesture.
        let clusterable = venues.filter { !overflowIDs.contains($0.id) }
        let spanLongitude = region?.span.longitudeDelta ?? fallbackSpanLongitude
        let cellDegrees = clusterCellDegrees(spanLongitude: spanLongitude)
        var built = clusters(for: clusterable, spanLongitude: spanLongitude)
        built = subdivideOversized(
            built,
            sourceVenues: clusterable,
            cellDegrees: cellDegrees,
            visibleCount: visible.count
        )
        built = declutter(built, against: topPins, cellDegrees: cellDegrees)

        return MapAnnotationPlan(pins: topPins, dots: dots, clusters: built)
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
    /// cell's centroid. Deterministic output order (by id).
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

    /// Grid-cell key for one coordinate at a given cell size — the single
    /// definition `clusters(for:spanLongitude:)` and the subdivision pass
    /// below both use, so the two can never drift apart.
    private static func cellKey(lat: Double, lng: Double, cellDegrees: Double) -> String {
        let latIndex = Int((lat / cellDegrees).rounded(.down))
        let lngIndex = Int((lng / cellDegrees).rounded(.down))
        return "cluster-\(latIndex)-\(lngIndex)-\(Int(log2(cellDegrees).rounded()))"
    }

    /// Top `limit` OBSERVED venues by Work Fit, ties broken by id for
    /// deterministic output.
    private static func topScoringObserved(_ venues: [Venue], limit: Int) -> [Venue] {
        Array(
            venues
                .filter(\.isObserved)
                .sorted { lhs, rhs in
                    lhs.workScore != rhs.workScore ? lhs.workScore > rhs.workScore : lhs.id < rhs.id
                }
                .prefix(limit)
        )
    }

    /// Nearest `limit` venues to the region's centre, ties broken by id.
    /// Falls back to the model's existing order when the region is unknown
    /// (brewdesk#157's same "never silently reorder into nothing" caution).
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

    /// A member venue list for one already-built cluster, recomputed from
    /// its id rather than plumbed through as extra state — `clusters(for:)`
    /// stays a plain aggregate-only function every existing caller/test
    /// already depends on.
    private static func members(of cluster: VenueCluster, in venues: [Venue], cellDegrees: Double) -> [Venue] {
        venues.filter { cellKey(lat: $0.lat, lng: $0.lng, cellDegrees: cellDegrees) == cluster.id }
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

    /// bd#204: no single cluster may hold more than `maxClusterShare` of the
    /// venues visible in this plan — the direct fix for a bubble holding the
    /// majority of a street-level viewport. Each oversized cell is
    /// re-bucketed ONCE at half its cell size; a cell the finer grid still
    /// can't split (e.g. venues sharing one coordinate) is kept as-is rather
    /// than looping.
    static func subdivideOversized(
        _ clusters: [VenueCluster],
        sourceVenues: [Venue],
        cellDegrees: Double,
        visibleCount: Int
    ) -> [VenueCluster] {
        guard visibleCount > 0, cellDegrees > 0 else { return clusters }
        let threshold = Double(visibleCount) * maxClusterShare
        var result: [VenueCluster] = []
        let finerCell = cellDegrees / 2
        for cluster in clusters {
            guard Double(cluster.count) > threshold else {
                result.append(cluster)
                continue
            }
            let clusterMembers = members(of: cluster, in: sourceVenues, cellDegrees: cellDegrees)
            let subBuckets = Dictionary(grouping: clusterMembers) {
                cellKey(lat: $0.lat, lng: $0.lng, cellDegrees: finerCell)
            }
            if subBuckets.count <= 1 {
                // The finer grid didn't actually separate anything — keep
                // the original rather than subdividing into a no-op.
                result.append(cluster)
            } else {
                result.append(contentsOf: subBuckets.map { key, subMembers in aggregate(subMembers, id: key) })
            }
        }
        return result.sorted { $0.id < $1.id }
    }

    /// bd#204: a score pin and a cluster must never visually overlap — the
    /// pin (real evidence) always wins, so a cluster centroid landing on top
    /// of one of `pins` is nudged outward by one cell-width instead. Cluster
    /// COUNTS never change; only the drawn centroid moves.
    static func declutter(_ clusters: [VenueCluster], against pins: [Venue], cellDegrees: Double) -> [VenueCluster] {
        guard !pins.isEmpty, !clusters.isEmpty, cellDegrees > 0 else { return clusters }
        let exclusion = cellDegrees * 0.5
        return clusters.map { cluster in
            guard let overlapping = pins.first(where: { pin in
                abs(pin.lat - cluster.latitude) < exclusion && abs(pin.lng - cluster.longitude) < exclusion
            }) else { return cluster }

            let rawDLat = cluster.latitude - overlapping.lat
            let rawDLng = cluster.longitude - overlapping.lng
            let rawMagnitude = (rawDLat * rawDLat + rawDLng * rawDLng).squareRoot()
            // Exact overlap has no direction to push along — nudge
            // north-east, deterministically, rather than leaving it in place.
            let (dirLat, dirLng): (Double, Double) = rawMagnitude > 1e-9
                ? (rawDLat / rawMagnitude, rawDLng / rawMagnitude)
                : (0.7071, 0.7071)

            return VenueCluster(
                id: cluster.id,
                latitude: cluster.latitude + dirLat * exclusion,
                longitude: cluster.longitude + dirLng * exclusion,
                count: cluster.count,
                bestScore: cluster.bestScore,
                hasObservedVenue: cluster.hasObservedVenue
            )
        }
    }
}
