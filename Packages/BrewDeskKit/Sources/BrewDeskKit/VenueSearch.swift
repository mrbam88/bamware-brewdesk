import Foundation
import VenueKit

/// Local search over the loaded venue list (brewdesk#78).
///
/// Matching is case- and diacritic-insensitive ("cafe" finds "Café"),
/// prefix + contains, over venue name and neighborhood. Prefix matches rank
/// first (name before neighborhood); within a rank the incoming order — the
/// engine's work-score ranking — is preserved. Search never touches the wire:
/// it composes with `VenueFilter` over venues already on the device.
public enum VenueSearch {
    public static func apply(_ query: String, to venues: [Venue]) -> [Venue] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return venues }

        let ranked: [(venue: Venue, rank: Int)] = venues.compactMap { venue in
            let name = normalize(venue.name)
            let neighborhood = normalize(venue.neighborhood)
            if name.hasPrefix(needle) { return (venue, 0) }
            if neighborhood.hasPrefix(needle) { return (venue, 1) }
            if name.contains(needle) || neighborhood.contains(needle) { return (venue, 2) }
            return nil
        }
        // Stable: sorted(by:) keeps the original order within equal ranks.
        return ranked.sorted { $0.rank < $1.rank }.map(\.venue)
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// bd#200: widens the candidate pool for a settled search with venues the
    /// SERVER found city-wide that the local viewport filter (`apply` above)
    /// never had a chance to match — a café across town the current viewport
    /// never loaded. `local` already carries `apply`'s own prefix/contains
    /// rank; `serverOnly` is whatever the caller determined isn't already in
    /// `local` (by id). Re-ranks the union: exact/prefix name matches first,
    /// then by distance from `centerLat/Lng` — a citywide result set has no
    /// single "loaded order" to fall back on the way a single viewport does,
    /// so distance is the tiebreaker instead of server order.
    public static func mergeCityWide(
        query: String, local: [Venue], serverOnly: [Venue], centerLat: Double, centerLng: Double
    ) -> [Venue] {
        let needle = normalize(query)
        func rank(_ venue: Venue) -> Int {
            normalize(venue.name).hasPrefix(needle) ? 0 : 1
        }
        func distanceM(_ venue: Venue) -> Double {
            VenuesModel.metersBetween(centerLat, centerLng, venue.lat, venue.lng)
        }
        var seen = Set<String>()
        let deduped = (local + serverOnly).filter { seen.insert($0.id).inserted }
        return deduped.sorted { a, b in
            let (ra, rb) = (rank(a), rank(b))
            if ra != rb { return ra < rb }
            return distanceM(a) < distanceM(b)
        }
    }
}
