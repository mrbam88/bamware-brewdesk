import Foundation
import Observation
import VenueKit

/// Loads Bamware Picks (bamware-ai#301) for the Saved tab.
///
/// The section is optional by design. It shows only in `.loaded`, which
/// means "the engine answered with at least one pick". Every other outcome
/// (still loading, an empty list, an engine that predates the route and
/// answers 404, offline, a body that does not decode) leaves the Saved tab
/// exactly as it was before the feature: no placeholder, no spinner, no
/// error. A curated list is a nice-to-have, never a reason to show a
/// failure.
@MainActor
@Observable
public final class PicksModel {
    public enum Phase: Equatable, Sendable {
        /// Nothing requested yet.
        case idle
        /// First request in flight. Hidden: a section that may turn out
        /// empty must not flash a header.
        case loading
        /// At least one pick. The only visible phase.
        case loaded
        /// The engine answered with no picks. Hidden.
        case empty
        /// The request failed. Hidden, with no error UI.
        case failed
    }

    public private(set) var phase: Phase = .idle
    /// Sorted by rank, 1 first. Empty unless `phase == .loaded`.
    public private(set) var picks: [Pick] = []
    /// `YYYY-MM-DD`, as served.
    public private(set) var updatedAt: String?

    @ObservationIgnored
    private let service: (any PicksServing)?

    /// `service` is `nil` for a venue service that has no Picks capability;
    /// the model then stays hidden without making a request.
    public init(service: (any PicksServing)?) {
        self.service = service
    }

    /// True only when there is something to show.
    public var isVisible: Bool { phase == .loaded && !picks.isEmpty }

    public func load() async {
        guard let service else {
            phase = .empty
            return
        }
        // A refresh keeps the list on screen; only the first load is silent.
        if phase != .loaded { phase = .loading }
        do {
            let response = try await service.fetchPicks()
            if Task.isCancelled { return }
            picks = response.picks
            updatedAt = response.updatedAt
            phase = response.picks.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            if phase == .loading { phase = .idle }
        } catch {
            if Task.isCancelled {
                if phase == .loading { phase = .idle }
                return
            }
            // A list already on screen survives a failed refresh: stale
            // picks are harmless, a section that blinks out is not.
            if phase != .loaded {
                picks = []
                updatedAt = nil
                phase = .failed
            }
        }
    }
}

/// Words and dates for the Picks section, kept out of the views so they can
/// be tested without rendering anything.
public enum PicksWording {
    /// "Pick #1".
    public static func badge(rank: Int, locale: Locale = .current) -> String {
        String(format: String(localized: "Pick #%lld", locale: locale), locale: locale, rank)
    }

    /// VoiceOver's reading of the badge: "Bamware Pick number 1".
    public static func badgeAccessibilityLabel(rank: Int, locale: Locale = .current) -> String {
        String(format: String(localized: "Bamware Pick number %lld", locale: locale), locale: locale, rank)
    }

    /// "Visited Oct 27", or "Visited Dec 14, 2025" once the visit is in an
    /// earlier year than `now`. `nil` when `isoDay` is not a real date, so
    /// the row drops the line instead of printing a broken one.
    public static func visited(_ isoDay: String, now: Date = Date(), locale: Locale = .current) -> String? {
        guard let day = day(isoDay, now: now, locale: locale) else { return nil }
        return String(format: String(localized: "Visited %@", locale: locale), locale: locale, day)
    }

    /// "Updated Nov 24", same year rule as `visited`.
    public static func updated(_ isoDay: String?, now: Date = Date(), locale: Locale = .current) -> String? {
        guard let isoDay, let day = day(isoDay, now: now, locale: locale) else { return nil }
        return String(format: String(localized: "Updated %@", locale: locale), locale: locale, day)
    }

    /// The line in typographic quotes, trimmed.
    public static func quoted(_ blurb: String) -> String {
        "\u{201C}\(blurb.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}"
    }

    /// `YYYY-MM-DD` → "Oct 27" / "Dec 14, 2025". A calendar day has no time
    /// zone, so it is parsed and printed in UTC: a reader west of Greenwich
    /// must not see the day before.
    static func day(_ isoDay: String, now: Date, locale: Locale) -> String? {
        guard let date = parse(isoDay) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = utc
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "yMMMd")
        return formatter.string(from: date)
    }

    static func parse(_ isoDay: String) -> Date? {
        let parts = isoDay.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2])
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let components = DateComponents(year: year, month: month, day: dayOfMonth)
        // `isValidDate` rejects Feb 30 and month 13 instead of rolling over.
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }

    private static let utc = TimeZone(identifier: "UTC") ?? .gmt
}
