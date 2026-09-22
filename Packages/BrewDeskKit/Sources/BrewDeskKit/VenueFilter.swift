import Foundation
import VenueKit

/// Client-side filter predicate for the venue list (brewdesk#77).
///
/// The engine's wire predicate (`store.ts`) fails every floor for venues whose
/// value is unknown — and 99/100 live venues carry no seating claim, so any
/// seating selection (and therefore "everything selected") emptied the list.
/// Category filtering is an app-side display concern, so it happens here, over
/// the already-loaded list, with inclusive semantics:
///
/// - A selection that admits every option in its category (the weakest floor)
///   is no filter at all — identical results, unknowns included.
/// - A constraining floor excludes only venues KNOWN to sit below it. An
///   unknown or absent value is not evidence against a venue; the row UI
///   already shows "unknown" openly, so honesty lives in the rendering.
/// - Categories combine with AND, which is safe under the two rules above.
public struct VenueFilter: Equatable, Sendable {
    public var laptopFriendlyOnly: Bool
    public var minWifi: WifiMinimum?
    public var minOutlets: OutletMinimum?
    public var minSeating: SeatingMinimum?
    public var venueType: VenueTypeFilter?

    public init(
        laptopFriendlyOnly: Bool = false,
        minWifi: WifiMinimum? = nil,
        minOutlets: OutletMinimum? = nil,
        minSeating: SeatingMinimum? = nil,
        venueType: VenueTypeFilter? = nil
    ) {
        self.laptopFriendlyOnly = laptopFriendlyOnly
        self.minWifi = minWifi
        self.minOutlets = minOutlets
        self.minSeating = minSeating
        self.venueType = venueType
    }

    public func apply(to venues: [Venue], now: Date = Date()) -> [Venue] {
        venues.filter { matches($0, now: now) }
    }

    /// brewdesk#222: honest three-way outcome per venue, replacing the old
    /// binary in/out `matches` as the source of truth (`matches` below is
    /// now derived from this). A café with an unknown Wi-Fi claim used to be
    /// presented in the list exactly like a confirmed "fast Wi-Fi" match —
    /// which read to a user as "the filter does nothing / returns junk"
    /// (TestFlight build 28, venue-engine#147's app-side half). Splitting
    /// the outcome into three lets the UI show confirmed matches first and
    /// unknowns separately, instead of blending them.
    ///
    /// - `.confirmed`: every constrained attribute is KNOWN and meets its
    ///   floor.
    /// - `.unknown`: nothing constrained is known to fail, but at least one
    ///   constrained attribute's value isn't in the known vocabulary (e.g.
    ///   `"unknown"`, or absent — no seating claim at all).
    /// - `.excluded`: some constrained attribute is KNOWN to sit below its
    ///   floor. This is the only case `matches`/`apply` ever drop a venue
    ///   for — identical to the pre-#222 behavior.
    ///
    /// No active constraint (every filter left at its default/weakest,
    /// venueType unset) → every venue is `.confirmed`, matching the
    /// established "all-selected == no-filter" rule.
    public enum FilterMatch: Equatable, Sendable {
        case confirmed
        case unknown
        case excluded
    }

    public func classify(_ venue: Venue, now: Date = Date()) -> FilterMatch {
        var sawUnknown = false

        if laptopFriendlyOnly {
            switch Self.laptopMatch(venue, now: now) {
            case .fail: return .excluded
            case .unknown: sawUnknown = true
            case .pass: break
            }
        }
        // Weakest floors admit every option — all-selected == no-filter —
        // so they never constrain the classification at all (no pass/fail/
        // unknown outcome is even asked for).
        if let floor = minWifi, floor != .slow {
            switch Self.tierMatch(value: venue.attributes.wifi.value, floor: floor.rawValue, tiers: Self.wifiTiers) {
            case .fail: return .excluded
            case .unknown: sawUnknown = true
            case .pass: break
            }
        }
        if let floor = minOutlets, floor != .scarce {
            switch Self.tierMatch(value: venue.attributes.outlets.value, floor: floor.rawValue, tiers: Self.amountTiers) {
            case .fail: return .excluded
            case .unknown: sawUnknown = true
            case .pass: break
            }
        }
        if let floor = minSeating, floor != .scarce {
            switch Self.tierMatch(value: venue.attributes.seating?.value, floor: floor.rawValue, tiers: Self.amountTiers) {
            case .fail: return .excluded
            case .unknown: sawUnknown = true
            case .pass: break
            }
        }
        // venueType has no "unknown" concept of its own — an absent
        // `venue.venueType` defaults to "cafe" (matching every other read
        // of this field), so it's always known.
        if let venueType, (venue.venueType ?? "cafe") != venueType.rawValue {
            return .excluded
        }

        return sawUnknown ? .unknown : .confirmed
    }

    public func matches(_ venue: Venue, now: Date = Date()) -> Bool {
        switch classify(venue, now: now) {
        case .confirmed, .unknown: true
        case .excluded: false
        }
    }

    private enum AttributeMatch { case pass, fail, unknown }

    private static func laptopMatch(_ venue: Venue, now: Date) -> AttributeMatch {
        let policy = venue.attributes.laptopPolicy.value
        if policy == "discouraged" { return .fail }
        if policy == "weekends_banned", isWeekendInNY(now) { return .fail }
        if policy == "unknown" { return .unknown }
        return .pass
    }

    private static func tierMatch(value: String?, floor: String, tiers: [String: Int]) -> AttributeMatch {
        guard let value, let tier = tiers[value] else { return .unknown }
        guard let floorTier = tiers[floor] else { return .pass }
        return tier < floorTier ? .fail : .pass
    }

    // Tier orders mirror the engine's WIFI_ORDER / OUTLET_ORDER / SEATING_ORDER.
    // Values outside the vocabulary ("unknown", future strings) have no tier
    // — `.unknown` for classification purposes, and (per `matches`) never
    // fail a floor either.
    private static let wifiTiers = ["slow": 1, "ok": 2, "fast": 3]
    private static let amountTiers = ["scarce": 1, "some": 2, "plenty": 3]

    /// Engine parity for `laptops=friendly`: weekend-banned venues drop out
    /// only on New York weekends (`store.ts` `isWeekendInNY`).
    static func isWeekendInNY(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar.isDateInWeekend(date)
    }
}
