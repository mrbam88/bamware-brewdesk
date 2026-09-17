import MapKit
import VenueKit

/// One grid-cell's worth of venues collapsed into a single map annotation.
public struct VenueCluster: Identifiable, Hashable, Sendable {
    /// Stable per zoom level: grid indices + the quantized cell exponent, so
    /// panning at an unchanged zoom keeps cluster identity (no churn).
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

/// What the map should draw for the current venues + camera (brewdesk#54).
///
/// Representation only — no styling. Views decide what a pin/dot/cluster
/// looks like (adjustable under brewdesk#55) without touching this logic.
public enum MapAnnotationPlan: Equatable {
    /// Few enough venues in view for full score pins.
    case pins([Venue])
    /// Mid density: cheap score-tier dots, one per venue.
    case dots([Venue])
    /// High density: grid clusters with count pills.
    case clusters([VenueCluster])

    public var annotationCount: Int {
        switch self {
        case .pins(let venues): venues.count
        case .dots(let venues): venues.count
        case .clusters(let clusters): clusters.count
        }
    }

    /// Whether this plan already renders the venue as an individual annotation
    /// (the screen adds a selected-pin overlay only when it does not).
    public func containsVenue(id: String) -> Bool {
        switch self {
        case .pins(let venues), .dots(let venues): venues.contains { $0.id == id }
        case .clusters: false
        }
    }
}

/// Pure, unit-tested planning: viewport culling with a margin, then a
/// zoom/density-dependent representation. Never called mid-gesture — the map
/// screen re-plans only when a camera move ends.
public enum MapAnnotationPlanner {
    /// At or below this many visible venues, every one gets a full pin.
    public static let pinLimit = 25
    /// At or below this many, score dots; above, clusters.
    public static let dotLimit = 150
    /// Dot mode renders at most this many dots — the best-ranked visible
    /// venues (the model orders by Work Fit). Fewer, smarter pins (#55) and
    /// fewer hosted annotation views: on-simulator, per-frame pan cost scales
    /// with annotation count before anything else (brewdesk#54 measurements).
    public static let dotBudget = 40
    /// Extra region kept annotated on every side (fraction of the span), so
    /// a pan shorter than half a screen never uncovers un-annotated map.
    public static let cullMargin = 0.5
    /// Cluster grid targets about this many cells across the viewport.
    /// Deliberately coarse: with the whole dataset clustered, the citywide
    /// pill count stays in the dozens (~25 for the 2,180-venue fixture at the
    /// default zoom) — per-frame pan cost scales with hosted annotation views
    /// before anything else, so fewer, denser pills IS the perf fix (#54/#55).
    public static let targetCellsAcross = 1.5
    /// Cluster-grid span used only when the camera region is genuinely
    /// unknown (brewdesk#157) — the same span the map screen's initial
    /// camera opens with, so a cold-start plan groups venues the same way
    /// the first real region would.
    public static let fallbackSpanLongitude = 0.035

    /// - Parameter region: the current camera viewport, or `nil` when it has
    ///   never been observed (cold start before the first camera settle) or a
    ///   `MapProxy` conversion failed. Either way this must never render as
    ///   an empty plan while `venues` is non-empty (brewdesk#157) — a stale
    ///   or unknown region falls back to the un-culled venue list instead of
    ///   silently hiding every pin.
    public static func plan(venues: [Venue], region: MKCoordinateRegion?) -> MapAnnotationPlan {
        let visible = candidates(venues: venues, region: region)
        if visible.count <= pinLimit { return .pins(visible) }
        if visible.count <= dotLimit { return .dots(Array(visible.prefix(dotBudget))) }
        // Cluster the WHOLE dataset, not the culled set: the grid is absolute,
        // so at an unchanged zoom every pan yields the identical cluster list —
        // zero annotation churn — and the pill count stays bounded by the grid
        // coarseness, not the venue count.
        return .clusters(clusters(for: venues, spanLongitude: region?.span.longitudeDelta ?? fallbackSpanLongitude))
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
            let latIndex = Int((venue.lat / cell).rounded(.down))
            let lngIndex = Int((venue.lng / cell).rounded(.down))
            let key = "cluster-\(latIndex)-\(lngIndex)-\(Int(log2(cell).rounded()))"
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
}
