import Foundation
import Testing
@testable import VenueKit

/// The parser's contract (brewdesk#50): parse the conservative OSM
/// `opening_hours` subset exactly, and refuse — returning `nil`, which the UI
/// renders as the raw string — anything it cannot be certain about. A wrong
/// open/closed claim is worse than no claim.
@Suite struct OpeningHoursTests {
    /// Fixed venue-local calendar so open-now assertions cannot drift with
    /// the machine running the tests.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    /// 2026-08-17 is a Monday; +dayOffset walks the week.
    private func date(weekdayOffset: Int, hour: Int, minute: Int) -> Date {
        calendar.date(
            from: DateComponents(
                year: 2026, month: 8, day: 17 + weekdayOffset, hour: hour, minute: minute
            )
        )!
    }

    // MARK: - Parsing the supported subset

    @Test func parsesDayRangeWithSingleSegment() throws {
        let hours = try #require(OpeningHours.parse("Mo-Fr 07:30-17:00"))
        let segment = OpeningHours.Segment(start: 7 * 60 + 30, end: 17 * 60)
        #expect(hours.segmentsByDay[0] == [segment])  // Monday
        #expect(hours.segmentsByDay[4] == [segment])  // Friday
        #expect(hours.segmentsByDay[5] == [])         // Saturday: unlisted = closed
        #expect(hours.segmentsByDay[6] == [])         // Sunday
    }

    @Test func parsesMultipleRulesAndDayLists() throws {
        let hours = try #require(
            OpeningHours.parse("Mo-Fr 07:30-17:00; Sa 08:00-17:30; Su 08:00-17:00")
        )
        #expect(hours.segmentsByDay[5] == [OpeningHours.Segment(start: 480, end: 1050)])
        #expect(hours.segmentsByDay[6] == [OpeningHours.Segment(start: 480, end: 1020)])

        let listed = try #require(OpeningHours.parse("Mo,We,Fr 09:00-12:00"))
        #expect(listed.segmentsByDay[0].count == 1)
        #expect(listed.segmentsByDay[1] == [])
        #expect(listed.segmentsByDay[2].count == 1)
    }

    @Test func parsesMultipleTimeSegmentsPerDay() throws {
        let hours = try #require(OpeningHours.parse("Mo-Fr 07:00-11:30,13:00-17:00"))
        #expect(hours.segmentsByDay[0] == [
            OpeningHours.Segment(start: 420, end: 690),
            OpeningHours.Segment(start: 780, end: 1020),
        ])
    }

    @Test func parsesOffDaysAndTimeOnlyRules() throws {
        let withOff = try #require(OpeningHours.parse("Mo-Sa 07:00-17:00; Su off"))
        #expect(withOff.segmentsByDay[6] == [])

        // No dayspec → applies to all seven days.
        let allDays = try #require(OpeningHours.parse("08:00-17:00"))
        for day in 0..<7 {
            #expect(allDays.segmentsByDay[day] == [OpeningHours.Segment(start: 480, end: 1020)])
        }
    }

    @Test func laterRulesOverrideEarlierDays() throws {
        // OSM semantics: "We 07:00-12:00" replaces Wednesday, not adds to it.
        let hours = try #require(OpeningHours.parse("Mo-Fr 07:00-17:00; We 07:00-12:00"))
        #expect(hours.segmentsByDay[2] == [OpeningHours.Segment(start: 420, end: 720)])
        #expect(hours.segmentsByDay[3] == [OpeningHours.Segment(start: 420, end: 1020)])
    }

    @Test func parsesWrappingDayRange() throws {
        let hours = try #require(OpeningHours.parse("Fr-Mo 10:00-16:00"))
        #expect(!hours.segmentsByDay[4].isEmpty)  // Fr
        #expect(!hours.segmentsByDay[5].isEmpty)  // Sa
        #expect(!hours.segmentsByDay[6].isEmpty)  // Su
        #expect(!hours.segmentsByDay[0].isEmpty)  // Mo
        #expect(hours.segmentsByDay[1].isEmpty)   // Tu
    }

    @Test func liveContractExampleParses() throws {
        // Verbatim from GET /v1/venues/curated-coffeeprojectnewyork.
        let hours = try #require(
            OpeningHours.parse("Mo-Fr 07:30-17:00; Sa 08:00-17:30; Su 08:00-17:00")
        )
        #expect(hours.dayGroups.count == 3)
    }

    // MARK: - Unparseable input falls back (returns nil)

    @Test(arguments: [
        "Daily 8am–5pm",              // human prose (the Corner Cafe fixture)
        "Mon–Fri 7am–7pm",            // wrong day tokens, wrong time format
        "24/7",                       // out of subset
        "Mo-Fr 07:00-17:00; PH off",  // public holidays out of subset
        "Mo-Fr sunrise-sunset",       // variable times out of subset
        "Fr 22:00-02:00",             // overnight span → refuse, never guess
        "Mo-Fr 25:00-26:00",          // invalid hour
        "Mo-Fr 07:60-17:00",          // invalid minute
        "Mo-Fr",                      // days without times
        "",                           // empty
        "   ",                        // whitespace only
        "Mo-Fr 07:00-17:00 extra",    // trailing junk
        "Su off",                     // parses but has zero open time
    ])
    func unparseableOrUncertainReturnsNil(raw: String) {
        #expect(OpeningHours.parse(raw) == nil)
    }

    // MARK: - Open-now, boundaries included

    @Test func openNowBoundariesAreInclusiveStartExclusiveEnd() throws {
        let hours = try #require(OpeningHours.parse("Mo-Fr 07:30-17:00"))
        // Wednesday (offset 2):
        #expect(!hours.isOpen(at: date(weekdayOffset: 2, hour: 7, minute: 29), calendar: calendar))
        #expect(hours.isOpen(at: date(weekdayOffset: 2, hour: 7, minute: 30), calendar: calendar))
        #expect(hours.isOpen(at: date(weekdayOffset: 2, hour: 16, minute: 59), calendar: calendar))
        #expect(!hours.isOpen(at: date(weekdayOffset: 2, hour: 17, minute: 0), calendar: calendar))
    }

    @Test func openNowRespectsDayMembership() throws {
        let hours = try #require(OpeningHours.parse("Mo-Fr 07:30-17:00; Sa-Su 08:00-18:00"))
        #expect(hours.isOpen(at: date(weekdayOffset: 5, hour: 8, minute: 0), calendar: calendar))   // Sa
        #expect(!hours.isOpen(at: date(weekdayOffset: 5, hour: 7, minute: 45), calendar: calendar)) // Sa pre-open
        #expect(hours.isOpen(at: date(weekdayOffset: 6, hour: 17, minute: 59), calendar: calendar)) // Su

        let weekdaysOnly = try #require(OpeningHours.parse("Mo-Fr 07:30-17:00"))
        // Unlisted Saturday is closed all day (OSM semantics).
        #expect(!weekdaysOnly.isOpen(at: date(weekdayOffset: 5, hour: 12, minute: 0), calendar: calendar))
    }

    @Test func openNowHandlesGapBetweenSegments() throws {
        let hours = try #require(OpeningHours.parse("Mo 07:00-11:30,13:00-17:00"))
        #expect(hours.isOpen(at: date(weekdayOffset: 0, hour: 11, minute: 29), calendar: calendar))
        #expect(!hours.isOpen(at: date(weekdayOffset: 0, hour: 12, minute: 0), calendar: calendar))
        #expect(hours.isOpen(at: date(weekdayOffset: 0, hour: 13, minute: 0), calendar: calendar))
    }

    @Test func midnightEndIsRepresentable() throws {
        let hours = try #require(OpeningHours.parse("Mo 18:00-24:00"))
        #expect(hours.isOpen(at: date(weekdayOffset: 0, hour: 23, minute: 59), calendar: calendar))
        // 24:00 anywhere but the end of a span stays unparseable.
        #expect(OpeningHours.parse("Mo 24:00-06:00") == nil)
    }

    // MARK: - Display grouping

    @Test func dayGroupsMergeConsecutiveIdenticalDays() throws {
        let hours = try #require(OpeningHours.parse("Mo-Fr 07:30-17:00; Sa-Su 08:00-18:00"))
        let groups = hours.dayGroups
        #expect(groups.count == 2)
        #expect(groups[0].firstDay == 0)
        #expect(groups[0].lastDay == 4)
        #expect(groups[1].firstDay == 5)
        #expect(groups[1].lastDay == 6)
    }

    @Test func dayGroupsKeepClosedDaysVisible() throws {
        let hours = try #require(OpeningHours.parse("Mo-Fr 07:30-17:00"))
        let groups = hours.dayGroups
        #expect(groups.count == 2)
        #expect(groups[1].segments.isEmpty)  // Sa–Su shown as Closed, not omitted
    }
}

/// Additive decode of the business-info fields (brewdesk#50): detail payloads
/// may carry `website`/`phone`; list payloads without them must keep decoding.
@Suite struct BusinessInfoDecodeTests {
    private let baseJSON = """
    {"id":"v1","name":"Spot","lat":40.7,"lng":-74.0,"address":null,
     "neighborhood":"SoHo","borough":"Manhattan","hoursRaw":null,"vertical":"cafe",
     "attributes":{
       "wifi":{"value":"fast","source":"agent","confidence":0.8,"observedAt":"2026-08-15T00:00:00Z"},
       "outlets":{"value":"some","source":"agent","confidence":0.7,"observedAt":"2026-08-15T00:00:00Z"},
       "laptopPolicy":{"value":"unrestricted","source":"agent","confidence":0.7,"observedAt":"2026-08-15T00:00:00Z"},
       "noise":{"value":"moderate","source":"agent","confidence":0.6,"observedAt":"2026-08-15T00:00:00Z"}
     },
     "vibeTags":[],"workScore":80,"lastVerified":null}
    """

    @Test func decodesWithoutBusinessInfoFields() throws {
        // The list payload shape today: no website/phone anywhere.
        let venue = try JSONDecoder().decode(Venue.self, from: Data(baseJSON.utf8))
        #expect(venue.website == nil)
        #expect(venue.phone == nil)
    }

    @Test func decodesDetailPayloadWithBusinessInfo() throws {
        // Mirrors the live detail contract (curated-coffeeprojectnewyork).
        let json = baseJSON.replacingOccurrences(
            of: "\"vibeTags\":[],",
            with: """
            "vibeTags":[],"website":"https://coffeeprojectny.com/","phone":"+1-212-228-7888",
            """
        )
        let venue = try JSONDecoder().decode(Venue.self, from: Data(json.utf8))
        #expect(venue.website == "https://coffeeprojectny.com/")
        #expect(venue.phone == "+1-212-228-7888")
    }
}
