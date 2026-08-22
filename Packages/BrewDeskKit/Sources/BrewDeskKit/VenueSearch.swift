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
}
