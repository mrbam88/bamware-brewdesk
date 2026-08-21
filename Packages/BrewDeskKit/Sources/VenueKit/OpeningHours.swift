import Foundation

/// Conservative parser for the subset of OSM `opening_hours` syntax the venue
/// engine serves in `Venue.hoursRaw` (brewdesk#50), e.g.
/// `"Mo-Fr 07:30-17:00; Sa-Su 08:00-17:00"`.
///
/// Design rule: a wrong open/closed claim is worse than no claim. `parse`
/// returns `nil` for ANY construct outside the supported subset — `24/7`,
/// public holidays (`PH`), sunrise/sunset, overnight spans (`22:00-02:00`),
/// month/week selectors — and the UI falls back to showing the raw string.
///
/// Supported grammar (rules separated by `;`, later rules override earlier
/// ones for the days they name, days never named are closed — OSM semantics):
///
///     rule      = [dayspec " "] timespec
///     dayspec   = daypart ("," daypart)*        e.g. "Mo-Fr,Su"
///     daypart   = DAY | DAY "-" DAY             ranges may wrap (Fr-Mo)
///     timespec  = "off" | "closed" | span ("," span)*
///     span      = HH:MM "-" HH:MM               start < end, end <= 24:00
///
/// A rule with no dayspec applies to all seven days.
public struct OpeningHours: Hashable, Sendable {
    /// Half-open interval in minutes since midnight: open at `start`
    /// (inclusive), closed again at `end` (exclusive). `end` may be 1440.
    public struct Segment: Hashable, Sendable {
        public let start: Int
        public let end: Int

        public init(start: Int, end: Int) {
            self.start = start
            self.end = end
        }
    }

    /// Index 0 = Monday … 6 = Sunday. An empty array means closed that day.
    public let segmentsByDay: [[Segment]]
    /// The string this was parsed from, for provenance/debug display.
    public let raw: String

    // MARK: - Parsing

    private static let dayTokens = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    public static func parse(_ raw: String) -> OpeningHours? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // nil = day never named by any rule (closed, but distinguishes
        // "no rule at all" so a string with zero open segments is rejected).
        var byDay = [[Segment]?](repeating: nil, count: 7)

        for rulePart in trimmed.split(separator: ";") {
            let rule = rulePart.trimmingCharacters(in: .whitespaces)
            if rule.isEmpty { continue }  // tolerate a trailing ";"

            let parts = rule.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let days: [Int]
            let timePart: String
            switch parts.count {
            case 1:
                days = Array(0..<7)
                timePart = parts[0]
            case 2:
                guard let parsed = parseDays(parts[0]) else { return nil }
                days = parsed
                timePart = parts[1]
            default:
                return nil
            }

            guard let segments = parseTimes(timePart) else { return nil }
            for day in days { byDay[day] = segments }
        }

        let resolved = byDay.map { $0 ?? [] }
        // A parse that yields no open time at all is not a schedule.
        guard resolved.contains(where: { !$0.isEmpty }) else { return nil }
        return OpeningHours(segmentsByDay: resolved, raw: trimmed)
    }

    /// "Mo-Fr,Su" → [0,1,2,3,4,6]. Ranges may wrap ("Fr-Mo").
    private static func parseDays(_ part: String) -> [Int]? {
        var days: Set<Int> = []
        for piece in part.split(separator: ",") {
            let bounds = piece.split(separator: "-", omittingEmptySubsequences: false)
            switch bounds.count {
            case 1:
                guard let day = dayTokens.firstIndex(of: String(bounds[0])) else { return nil }
                days.insert(day)
            case 2:
                guard let start = dayTokens.firstIndex(of: String(bounds[0])),
                      let end = dayTokens.firstIndex(of: String(bounds[1]))
                else { return nil }
                var day = start
                while true {
                    days.insert(day)
                    if day == end { break }
                    day = (day + 1) % 7
                }
            default:
                return nil
            }
        }
        return days.sorted()
    }

    /// "07:00-11:30,13:00-17:00" → two segments; "off"/"closed" → [].
    private static func parseTimes(_ part: String) -> [Segment]? {
        if part == "off" || part == "closed" { return [] }
        var segments: [Segment] = []
        for piece in part.split(separator: ",", omittingEmptySubsequences: false) {
            let bounds = piece.split(separator: "-", omittingEmptySubsequences: false)
            guard bounds.count == 2,
                  let start = parseMinutes(bounds[0], isEnd: false),
                  let end = parseMinutes(bounds[1], isEnd: true),
                  start < end  // overnight spans are out of subset → fallback
            else { return nil }
            segments.append(Segment(start: start, end: end))
        }
        return segments.sorted { $0.start < $1.start }
    }

    /// "HH:MM" → minutes since midnight. "24:00" allowed only as an end.
    private static func parseMinutes(_ text: Substring, isEnd: Bool) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count <= 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...59).contains(minute)
        else { return nil }
        if hour == 24 { return (isEnd && minute == 0) ? 1440 : nil }
        guard (0...23).contains(hour) else { return nil }
        return hour * 60 + minute
    }

    // MARK: - Queries

    /// Open at `start` (inclusive), closed at `end` (exclusive) — so a café
    /// listed `07:30-17:00` is open at 07:30 sharp and closed at 17:00 sharp.
    public func isOpen(at date: Date, calendar: Calendar = .current) -> Bool {
        // Calendar weekday: 1 = Sunday … 7 = Saturday → our 0 = Monday … 6.
        let weekday = calendar.component(.weekday, from: date)
        let day = (weekday + 5) % 7
        let minutes = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        return segmentsByDay[day].contains { $0.start <= minutes && minutes < $0.end }
    }

    /// Consecutive days (Monday-first) sharing an identical schedule, for
    /// compact display ("Mon–Fri 7:30 AM–5:00 PM"). Covers all seven days;
    /// groups with empty `segments` are closed days.
    public struct DayGroup: Hashable, Sendable, Identifiable {
        /// 0 = Monday … 6 = Sunday.
        public let firstDay: Int
        public let lastDay: Int
        public let segments: [Segment]

        public var id: Int { firstDay }
    }

    public var dayGroups: [DayGroup] {
        var groups: [DayGroup] = []
        for day in 0..<7 {
            if let last = groups.last, last.segments == segmentsByDay[day],
               last.lastDay == day - 1 {
                groups[groups.count - 1] = DayGroup(
                    firstDay: last.firstDay, lastDay: day, segments: last.segments
                )
            } else {
                groups.append(DayGroup(firstDay: day, lastDay: day, segments: segmentsByDay[day]))
            }
        }
        return groups
    }
}
