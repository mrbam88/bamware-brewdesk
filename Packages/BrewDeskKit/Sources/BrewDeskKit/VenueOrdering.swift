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
}
