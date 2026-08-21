import Foundation

/// Locale-driven display formatting for `OpeningHours` (brewdesk#56).
///
/// The parser's internal model stays 24-hour minutes-since-midnight; ONLY
/// display goes through the locale. en_US renders "7:30 AM – 5:00 PM",
/// 24-hour locales (de_DE, …) render "07:30 – 17:00" — the hour cycle is
/// the locale's choice, never hard-coded.
///
/// Times are formatted on a fixed GMT reference day, so a minutes value maps
/// to exactly that wall-clock time — immune to the device time zone's DST
/// transitions (02:30 exists every day in GMT).
public enum OpeningHoursFormatter {
    /// Joiner between a segment's open and close times: "7:30 AM – 5:00 PM".
    private static let timeRangeSeparator = " – "
    /// Joiner between multiple segments on one day (split shifts).
    private static let segmentSeparator = ", "

    /// "7:30 AM" (en_US) / "07:30" (de_DE) for minutes since midnight.
    /// 1440 (a "24:00" close) renders as midnight.
    public static func timeLabel(minutes: Int, locale: Locale = .autoupdatingCurrent) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        calendar.locale = locale
        // 2001-01-01 00:00:00 GMT — any fixed date works; GMT has no DST.
        let date = Date(timeIntervalSinceReferenceDate: TimeInterval(minutes * 60))
        let style = Date.FormatStyle(
            locale: locale, calendar: calendar, timeZone: calendar.timeZone
        ).hour(.defaultDigits(amPM: .abbreviated)).minute()
        return date.formatted(style)
    }

    /// "7:30 AM – 5:00 PM" per segment, segments joined with ", ".
    public static func timesLabel(
        _ segments: [OpeningHours.Segment],
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        segments.map { segment in
            timeLabel(minutes: segment.start, locale: locale)
                + timeRangeSeparator
                + timeLabel(minutes: segment.end, locale: locale)
        }.joined(separator: segmentSeparator)
    }

    /// "Mon–Fri" / "Sat" via the locale's short weekday symbols.
    /// `DayGroup` days are Monday-first (0…6); `shortWeekdaySymbols` is
    /// Sunday-first.
    public static func dayGroupLabel(
        _ group: OpeningHours.DayGroup,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let symbols = calendar.shortWeekdaySymbols
        let first = symbols[(group.firstDay + 1) % 7]
        guard group.lastDay != group.firstDay else { return first }
        return "\(first)–\(symbols[(group.lastDay + 1) % 7])"
    }
}
