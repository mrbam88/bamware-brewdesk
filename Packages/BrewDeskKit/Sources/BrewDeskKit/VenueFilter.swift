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

    public func matches(_ venue: Venue, now: Date = Date()) -> Bool {
        if laptopFriendlyOnly {
            let policy = venue.attributes.laptopPolicy.value
            if policy == "discouraged" { return false }
            if policy == "weekends_banned", Self.isWeekendInNY(now) { return false }
        }
        // Weakest floors admit every option — all-selected == no-filter.
        if let floor = minWifi, floor != .slow,
           let tier = Self.wifiTiers[venue.attributes.wifi.value],
           tier < Self.wifiTiers[floor.rawValue]! {
            return false
        }
        if let floor = minOutlets, floor != .scarce,
           let tier = Self.amountTiers[venue.attributes.outlets.value],
           tier < Self.amountTiers[floor.rawValue]! {
            return false
        }
        if let floor = minSeating, floor != .scarce,
           let seating = venue.attributes.seating,
           let tier = Self.amountTiers[seating.value],
           tier < Self.amountTiers[floor.rawValue]! {
            return false
        }
        if let venueType, (venue.venueType ?? "cafe") != venueType.rawValue {
            return false
        }
        return true
    }

    // Tier orders mirror the engine's WIFI_ORDER / OUTLET_ORDER / SEATING_ORDER.
    // Values outside the vocabulary ("unknown", future strings) have no tier
    // and therefore never fail a floor.
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
