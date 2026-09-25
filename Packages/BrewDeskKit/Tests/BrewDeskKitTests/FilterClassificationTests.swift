import Foundation
import Testing
@testable import BrewDeskKit
import VenueKit

/// brewdesk#222 — `VenueFilter.classify` classification matrix: every
/// dimension (laptop/Wi-Fi/outlets/seating/venueType) × known-pass /
/// known-fail / unknown, plus the combination and no-constraint rules the
/// issue spells out. `FilterInclusivityTests` already covers `matches`/
/// `apply`'s binary in/out behavior (unchanged by this ticket); this suite
/// is the new three-way `classify` outcome those same rules now derive from.
@Suite struct FilterClassificationTests {
    private static let observedAt = "2026-08-01T00:00:00Z"

    private static func venue(
        wifi: String, outlets: String, seating: String?, laptopPolicy: String,
        venueType: String? = "cafe"
    ) -> Venue {
        func claim(_ value: String) -> Claim {
            Claim(value: value, source: "curated", confidence: 0.8, observedAt: observedAt)
        }
        return Venue(
            id: "v", name: "v", lat: 40.7359, lng: -73.9911, address: nil,
            neighborhood: "Union Square", borough: "Manhattan", hoursRaw: nil, vertical: "cafe",
            attributes: VenueAttributes(
                wifi: claim(wifi), outlets: claim(outlets), laptopPolicy: claim(laptopPolicy),
                noise: claim("moderate"), seating: seating.map(claim)
            ),
            vibeTags: [], workScore: 70, lastVerified: nil, distanceM: nil, venueType: venueType
        )
    }

    // MARK: - No active constraint

    @Test func noConstraintIsAlwaysConfirmed() {
        let filter = VenueFilter()
        let v = Self.venue(wifi: "unknown", outlets: "unknown", seating: nil, laptopPolicy: "discouraged")
        #expect(filter.classify(v) == .confirmed)
    }

    @Test func weakestFloorSelectionsAreAlsoNoConstraint() {
        // .slow / .scarce / .scarce admit every option — "all-selected ==
        // no-filter" (VenueFilter's own doc comment) — so even a venue with
        // nothing but unknowns classifies as confirmed.
        let filter = VenueFilter(minWifi: .slow, minOutlets: .scarce, minSeating: .scarce)
        let v = Self.venue(wifi: "unknown", outlets: "unknown", seating: nil, laptopPolicy: "unrestricted")
        #expect(filter.classify(v) == .confirmed)
    }

    // MARK: - Wi-Fi

    @Test func wifiKnownPass() {
        let filter = VenueFilter(minWifi: .ok)
        let v = Self.venue(wifi: "fast", outlets: "plenty", seating: "plenty", laptopPolicy: "unrestricted")
        #expect(filter.classify(v) == .confirmed)
    }

    @Test func wifiKnownFail() {
        let filter = VenueFilter(minWifi: .ok)
        let v = Self.venue(wifi: "slow", outlets: "plenty", seating: "plenty", laptopPolicy: "unrestricted")
        #expect(filter.classify(v) == .excluded)
    }

    @Test func wifiUnknown() {
        let filter = VenueFilter(minWifi: .fast)
        let v = Self.venue(wifi: "unknown", outlets: "plenty", seating: "plenty", laptopPolicy: "unrestricted")
        #expect(filter.classify(v) == .unknown)
    }

    // MARK: - Outlets

    @Test func outletsKnownPass() {
        let filter = VenueFilter(minOutlets: .some)
        let v = Self.venue(wifi: "fast", outlets: "plenty", seating: "plenty", laptopPolicy: "unrestricted")
        #expect(filter.classify(v) == .confirmed)
    }

    @Test func outletsKnownFail() {
        let filter = VenueFilter(minOutlets: .plenty)
        let v = Self.venue(wifi: "fast", outlets: "some", seating: "plenty", laptopPolicy: "unrestricted")
        #expect(filter.classify(v) == .excluded)
    }

    @Test func outletsUnknown() {
        let filter = VenueFilter(minOutlets: .plenty)
        let v = Self.venue(wifi: "fast", outlets: "unknown", seating: "plenty", laptopPolicy: "unrestricted")
        #expect(filter.classify(v) == .unknown)
    }

    // MARK: - Seating (absent claim, the common live shape)

    @Test func seatingKnownPass() {
        let filter = VenueFilter(minSeating: .some)
        let v = Self.venue(wifi: "fast", outlets: "plenty", seating: "plenty", laptopPolicy: "unrestricted")
        #expect(filter.classify(v) == .confirmed)
    }

    @Test func seatingKnownFail() {
        let filter = VenueFilter(minSeating: .plenty)
        let v = Self.venue(wifi: "fast", outlets: "plenty", seating: "some", laptopPolicy: "unrestricted")
        #expect(filter.classify(v) == .excluded)
    }

    @Test func seatingAbsentClaimIsUnknown() {
        // 99/100 live venues carry no seating claim at all (brewdesk#77) —
        // the exact shape the confirmed/unknown split exists for.
        let filter = VenueFilter(minSeating: .some)
        let v = Self.venue(wifi: "fast", outlets: "plenty", seating: nil, laptopPolicy: "unrestricted")
        #expect(filter.classify(v) == .unknown)
    }

    // MARK: - Laptop friendly

    @Test func laptopKnownPass() {
        let filter = VenueFilter(laptopFriendlyOnly: true)
        let v = Self.venue(wifi: "fast", outlets: "plenty", seating: "plenty", laptopPolicy: "unrestricted")
        #expect(filter.classify(v) == .confirmed)
    }

    @Test func laptopKnownFail() {
        let filter = VenueFilter(laptopFriendlyOnly: true)
        let v = Self.venue(wifi: "fast", outlets: "plenty", seating: "plenty", laptopPolicy: "discouraged")
        #expect(filter.classify(v) == .excluded)
    }

    @Test func laptopUnknown() {
        let filter = VenueFilter(laptopFriendlyOnly: true)
        let v = Self.venue(wifi: "fast", outlets: "plenty", seating: "plenty", laptopPolicy: "unknown")
        #expect(filter.classify(v) == .unknown)
    }

    /// Weekend-banned is a KNOWN fail, but only on an actual NY weekend —
    /// the existing `matches` rule, carried into `classify` unchanged.
    @Test func laptopWeekendsBannedIsKnownFailOnlyOnAWeekend() {
        let filter = VenueFilter(laptopFriendlyOnly: true)
        let v = Self.venue(wifi: "fast", outlets: "plenty", seating: "plenty", laptopPolicy: "weekends_banned")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let saturday = utc.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 12))!
        let tuesday = utc.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 12))!
        #expect(filter.classify(v, now: saturday) == .excluded)
        #expect(filter.classify(v, now: tuesday) == .confirmed)
    }

    // MARK: - Venue type (brewdesk#240)

    @Test func venueTypeKnownPass() {
        let filter = VenueFilter(selectedVenueTypes: [.cafe])
        let v = Self.venue(wifi: "fast", outlets: "plenty", seating: "plenty", laptopPolicy: "unrestricted", venueType: "cafe")
        #expect(filter.classify(v) == .confirmed)
    }

    @Test func venueTypeKnownFail() {
        let filter = VenueFilter(selectedVenueTypes: [.library])
        let v = Self.venue(wifi: "fast", outlets: "plenty", seating: "plenty", laptopPolicy: "unrestricted", venueType: "cafe")
        #expect(filter.classify(v) == .excluded)
    }

    /// brewdesk#240: an absent/unrecognized `venueType` is `.unknown` — it
    /// is NEVER excluded by a narrowed type selection (the old `?? "cafe"`
    /// default is gone), but it's also never a confirmed match: exactly the
    /// same "unknown is not evidence against a venue, but isn't proof for
    /// it either" rule every other dimension in this file already follows.
    @Test func venueTypeAbsentIsUnknownNeverExcludedNeverDefaultedToCafe() {
        let filter = VenueFilter(selectedVenueTypes: [.cafe])
        let v = Self.venue(wifi: "fast", outlets: "plenty", seating: "plenty", laptopPolicy: "unrestricted", venueType: nil)
        #expect(filter.classify(v) == .unknown)
    }

    // MARK: - Combinations

    /// A known fail on ANY dimension excludes outright, even alongside an
    /// unknown on another — exclusion always wins over unknown.
    @Test func aKnownFailExcludesEvenWithAnUnknownElsewhere() {
        let filter = VenueFilter(minWifi: .fast, minOutlets: .plenty)
        let v = Self.venue(wifi: "unknown", outlets: "scarce", seating: "plenty", laptopPolicy: "unrestricted")
        #expect(filter.classify(v) == .excluded)
    }

    /// No known fail anywhere, but at least one unknown — the WeWork shape
    /// (TestFlight build 28): Work Fit evidenced, Wi-Fi unknown, under a
    /// "fast Wi-Fi" filter.
    @Test func noKnownFailWithAnUnknownIsUnknownNotConfirmed() {
        let filter = VenueFilter(minWifi: .fast, minOutlets: .some)
        let v = Self.venue(wifi: "unknown", outlets: "plenty", seating: "plenty", laptopPolicy: "unrestricted")
        #expect(filter.classify(v) == .unknown)
    }

    /// Every constrained dimension known and passing → confirmed, even with
    /// several dimensions active at once.
    @Test func everyDimensionKnownAndPassingIsConfirmed() {
        let filter = VenueFilter(
            laptopFriendlyOnly: true, minWifi: .fast, minOutlets: .plenty,
            minSeating: .some, selectedVenueTypes: [.cafe]
        )
        let v = Self.venue(wifi: "fast", outlets: "plenty", seating: "plenty", laptopPolicy: "unrestricted", venueType: "cafe")
        #expect(filter.classify(v) == .confirmed)
    }

    // MARK: - `matches` is derived from `classify`

    @Test func matchesIsTrueForConfirmedAndUnknownFalseForExcluded() {
        let filter = VenueFilter(minWifi: .fast)
        let confirmed = Self.venue(wifi: "fast", outlets: "plenty", seating: "plenty", laptopPolicy: "unrestricted")
        let unknown = Self.venue(wifi: "unknown", outlets: "plenty", seating: "plenty", laptopPolicy: "unrestricted")
        let excluded = Self.venue(wifi: "slow", outlets: "plenty", seating: "plenty", laptopPolicy: "unrestricted")
        #expect(filter.matches(confirmed))
        #expect(filter.matches(unknown))
        #expect(!filter.matches(excluded))
    }
}
