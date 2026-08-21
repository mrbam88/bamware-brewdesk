import Foundation
import Testing
@testable import VenueKit

/// Locale display formatting (brewdesk#56): the parser's model stays 24h;
/// display follows the locale's hour cycle. en_US must read 12-hour AM/PM,
/// a 24-hour locale (de_DE) must stay 24-hour — never hard-coded either way.
@Suite struct OpeningHoursFormatterTests {
    private let enUS = Locale(identifier: "en_US")
    private let deDE = Locale(identifier: "de_DE")

    /// ICU emits narrow no-break spaces (U+202F) before AM/PM on modern iOS;
    /// fold every space flavor to a plain space so assertions read literally.
    private func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    // MARK: - Time labels

    @Test func enUSRendersTwelveHourClock() {
        #expect(plain(OpeningHoursFormatter.timeLabel(minutes: 7 * 60 + 30, locale: enUS)) == "7:30 AM")
        #expect(plain(OpeningHoursFormatter.timeLabel(minutes: 17 * 60, locale: enUS)) == "5:00 PM")
        #expect(plain(OpeningHoursFormatter.timeLabel(minutes: 0, locale: enUS)) == "12:00 AM")
        #expect(plain(OpeningHoursFormatter.timeLabel(minutes: 12 * 60, locale: enUS)) == "12:00 PM")
    }

    @Test func twentyFourHourLocaleStaysTwentyFourHour() {
        #expect(OpeningHoursFormatter.timeLabel(minutes: 7 * 60 + 30, locale: deDE) == "07:30")
        #expect(OpeningHoursFormatter.timeLabel(minutes: 17 * 60, locale: deDE) == "17:00")
        #expect(OpeningHoursFormatter.timeLabel(minutes: 0, locale: deDE) == "00:00")
    }

    @Test func midnightCloseRendersAsMidnight() {
        // A "…-24:00" close parses to 1440 minutes.
        #expect(plain(OpeningHoursFormatter.timeLabel(minutes: 1440, locale: enUS)) == "12:00 AM")
        #expect(OpeningHoursFormatter.timeLabel(minutes: 1440, locale: deDE) == "00:00")
    }

    // MARK: - Segment ranges (the AC string)

    @Test func enUSSegmentReadsLikeTheAcceptanceCriterion() throws {
        let hours = try #require(OpeningHours.parse("Mo-Fr 07:30-17:00"))
        let monday = hours.segmentsByDay[0]
        #expect(plain(OpeningHoursFormatter.timesLabel(monday, locale: enUS)) == "7:30 AM – 5:00 PM")
        #expect(OpeningHoursFormatter.timesLabel(monday, locale: deDE) == "07:30 – 17:00")
    }

    @Test func splitShiftsJoinWithCommas() throws {
        let hours = try #require(OpeningHours.parse("Mo 07:00-11:30,13:00-17:00"))
        let monday = hours.segmentsByDay[0]
        #expect(plain(OpeningHoursFormatter.timesLabel(monday, locale: enUS))
            == "7:00 AM – 11:30 AM, 1:00 PM – 5:00 PM")
    }

    // MARK: - Day-group labels

    @Test func dayGroupLabelsUseLocalizedShortSymbols() throws {
        let hours = try #require(OpeningHours.parse("Mo-Fr 07:30-17:00; Sa-Su 08:00-17:00"))
        let groups = hours.dayGroups
        #expect(groups.count == 2)
        #expect(OpeningHoursFormatter.dayGroupLabel(groups[0], locale: enUS) == "Mon–Fri")
        #expect(OpeningHoursFormatter.dayGroupLabel(groups[1], locale: enUS) == "Sat–Sun")

        let saturdayOnly = try #require(OpeningHours.parse("Sa 08:00-17:00; Su off"))
        let single = try #require(saturdayOnly.dayGroups.first {
            $0.firstDay == 5 && $0.lastDay == 5
        })
        #expect(OpeningHoursFormatter.dayGroupLabel(single, locale: enUS) == "Sat")
        // Localized, not hard-coded English: German short symbols differ.
        #expect(OpeningHoursFormatter.dayGroupLabel(groups[0], locale: deDE) != "Mon–Fri")
        #expect(OpeningHoursFormatter.dayGroupLabel(groups[0], locale: deDE).hasPrefix("Mo"))
    }
}
