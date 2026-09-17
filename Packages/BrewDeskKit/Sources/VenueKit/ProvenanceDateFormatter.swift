import Foundation

/// Locale-driven display formatting for a `Claim.observedAt` string
/// (brewdesk#142). The engine sends a calendar date — "2026-08-01" means
/// "the visit was August 1st," not "midnight UTC on August 1st" — so the
/// ISO string must never reach the UI verbatim (screenshot QA flagged
/// "Curated · 75% confidence · 2026-08-01" as raw and unfriendly).
///
/// Both the parse and the render side pin GMT, matching the house pattern
/// in `OpeningHoursFormatter`: an instant parsed at GMT midnight and
/// re-rendered in GMT always reads back as the same calendar day, in every
/// device time zone. Rendering that instant in the *device* zone instead —
/// every US zone sits behind GMT — would roll "2026-08-01" back to July 31
/// for anyone west of Greenwich. That off-by-one is the bug this type
/// exists to prevent; see `ProvenanceDateFormatterTests`.
public enum ProvenanceDateFormatter {
    private static let gmt = TimeZone(identifier: "GMT")!

    private static let parseFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = gmt
        return formatter
    }()

    /// "Aug 1, 2026" (en) / "1 ago 2026" (es) for a "yyyy-MM-dd"-prefixed
    /// `observedAt` string. Anything that doesn't parse as a calendar date
    /// (unexpected engine payload) falls back to the first 10 characters
    /// verbatim rather than showing nothing.
    public static func friendly(_ isoDate: String, locale: Locale = .autoupdatingCurrent) -> String {
        let day = String(isoDate.prefix(10))
        guard let date = parseFormatter.date(from: day) else { return day }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = gmt
        calendar.locale = locale
        let style = Date.FormatStyle(
            date: .abbreviated, time: .omitted, locale: locale, calendar: calendar, timeZone: gmt
        )
        return date.formatted(style)
    }
}
