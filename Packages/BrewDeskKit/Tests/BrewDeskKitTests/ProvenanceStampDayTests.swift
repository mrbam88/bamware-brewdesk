import Foundation
import Testing
import VenueKit
@testable import BrewDeskKit

/// brewdesk#142: the card provenance stamp ("Updated Aug 1 · curated") must
/// show the calendar day the engine sent, in every device time zone. It used
/// to parse in UTC and render in the device zone, so New York read "Jul 31".
@Suite(.serialized) struct ProvenanceStampDayTests {
    private let enUS = Locale(identifier: "en_US")

    private func claim(observedAt: String) -> Claim {
        Claim(value: "fast", source: "curated", confidence: 0.75, observedAt: observedAt)
    }

    @Test func stampDayDoesNotShiftInNewYork() throws {
        try withSystemTimeZone("America/New_York") {
            let date = try #require(ProvenanceStamp.observationDate(of: claim(observedAt: "2026-08-01")))
            #expect(date.formatted(ProvenanceStamp.dayStyle(month: .abbreviated, locale: enUS)) == "Aug 1")
            #expect(date.formatted(ProvenanceStamp.dayStyle(month: .wide, locale: enUS)) == "August 1")
        }
    }

    @Test func stampDayDoesNotShiftInLosAngelesAtYearStart() throws {
        try withSystemTimeZone("America/Los_Angeles") {
            let date = try #require(ProvenanceStamp.observationDate(of: claim(observedAt: "2026-01-01T00:00:00Z")))
            #expect(date.formatted(ProvenanceStamp.dayStyle(month: .abbreviated, locale: enUS)) == "Jan 1")
        }
    }

    private func withSystemTimeZone(_ identifier: String, _ body: () throws -> Void) rethrows {
        let original = ProcessInfo.processInfo.environment["TZ"]
        setenv("TZ", identifier, 1); tzset(); NSTimeZone.resetSystemTimeZone()
        defer {
            if let original { setenv("TZ", original, 1) } else { unsetenv("TZ") }
            tzset(); NSTimeZone.resetSystemTimeZone()
        }
        try body()
    }
}
