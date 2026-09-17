import VenueKit

/// Client-side venue ordering (brewdesk#159): a venue with no real
/// evidence behind its score (`!Venue.isObserved`) must never rank above
/// one the engine actually checked, even though both can carry the same
/// flat neutral `workScore`.
///
/// A stable partition, not a sort by score — observed venues keep the
/// server's own ranking among themselves, and so do unobserved ones; only
/// the two groups' relative position changes (observed group first).
/// Composes AFTER `VenueFilter.apply` and `VenueSearch.apply`, so a
/// search's prefix/contains match rank still wins inside each group.
public enum VenueOrdering {
    public static func observedFirst(_ venues: [Venue]) -> [Venue] {
        venues.filter(\.isObserved) + venues.filter { !$0.isObserved }
    }
}
