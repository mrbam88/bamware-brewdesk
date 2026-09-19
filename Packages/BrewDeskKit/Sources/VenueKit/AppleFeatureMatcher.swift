import Foundation

/// Dedupe logic for an Apple base-map POI label against our own listing
/// (brewdesk#182): "is this actually one of our venues, just drawn by
/// Apple's free base-map layer instead of our own pin?" A match is a
/// same-normalized-name venue within `matchRadiusMeters`. Pure and
/// MapKit-free so it's unit-testable without a simulator.
public enum AppleFeatureMatcher {
    /// Distance ticket bd#182 specifies for "not one of our pins".
    public static let matchRadiusMeters = 60.0

    /// The venue this Apple feature is actually one of ours, or `nil` when
    /// it's genuinely not in BrewDesk yet.
    public static func matchingVenue(
        name: String,
        lat: Double,
        lng: Double,
        in venues: [Venue]
    ) -> Venue? {
        let target = normalize(name)
        guard !target.isEmpty else { return nil }
        return venues.first { venue in
            normalize(venue.name) == target
                && metersBetween(venue.lat, venue.lng, lat, lng) < matchRadiusMeters
        }
    }

    /// Case/whitespace-insensitive name comparison — Apple and our engine
    /// don't always agree on capitalization or a trailing "Cafe" vs "Café".
    public static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Haversine distance in meters. Duplicated from `VenuesModel` (the
    /// BrewDeskKit-side call site) rather than shared: this file lives in
    /// VenueKit, which `VenuesModel` (BrewDeskKit) itself imports, so
    /// depending the other way would invert the package's layering.
    static func metersBetween(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let earthRadiusM = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLng / 2) * sin(dLng / 2)
        return earthRadiusM * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
