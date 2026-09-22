import VenueKit

/// Client-side venue ordering (brewdesk#159, brewdesk#213): a venue with no
/// real evidence behind its score (`!Venue.isRated`) must never rank above
/// one the engine actually checked/rated, even though both can carry the
/// same flat neutral `workScore`.
///
/// A stable partition, not a sort by score — rated venues keep the
/// server's own ranking among themselves, and so do unrated ones; only
/// the two groups' relative position changes (rated group first).
/// Composes AFTER `VenueFilter.apply` and `VenueSearch.apply`, so a
/// search's prefix/contains match rank still wins inside each group.
///
/// Uses `Venue.isRated` (brewdesk#213), not the older `isObserved` heuristic
/// directly — `isRated` already honors the server's explicit `scoreDisplay`
/// when present and falls back to `isObserved` only when the server has no
/// opinion (`.notProvided`), so this keeps working unchanged against a
/// server that hasn't shipped `scoreDisplay` yet.
public enum VenueOrdering {
    public static func observedFirst(_ venues: [Venue]) -> [Venue] {
        venues.filter(\.isRated) + venues.filter { !$0.isRated }
    }

    /// brewdesk#222: cafés (`venueType` nil or `"cafe"`) rank above every
    /// other `venueType` (coworking, library…) by default — a TestFlight
    /// report (build 28) showed a WeWork leading the filtered list purely
    /// because it happened to score higher, not because it's the kind of
    /// place a café search should lead with. Only applies while the user
    /// hasn't explicitly chosen a type via the type filter — `venueType`
    /// still exposes every type once chosen (`venueTypeChosen: true` is a
    /// no-op here, matching "keep them available via the type filter").
    ///
    /// A stable partition, like `observedFirst`: composing this AFTER that
    /// (the call site's convention) keeps each type group's own
    /// observed-first/score/search-rank order untouched — only the two
    /// groups' relative position changes (cafés first).
    public static func cafeDefaultFirst(_ venues: [Venue], venueTypeChosen: Bool) -> [Venue] {
        guard !venueTypeChosen else { return venues }
        return venues.filter(Self.isDefaultCafe) + venues.filter { !Self.isDefaultCafe($0) }
    }

    private static func isDefaultCafe(_ venue: Venue) -> Bool {
        (venue.venueType ?? "cafe") == "cafe"
    }
}
