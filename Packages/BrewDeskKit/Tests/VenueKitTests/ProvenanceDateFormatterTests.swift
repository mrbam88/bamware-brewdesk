import Foundation
import Testing
@testable import VenueKit

/// Friendly rendering of a `Claim.observedAt` calendar date (brewdesk#142).
/// The critical case is the time-zone pin: "2026-08-01" is a calendar date,
/// not an instant, and must render as Aug 1 everywhere — including from a
/// device sitting behind GMT, where a naive UTC-parse-then-local-render
/// would roll it back to July 31.
@Suite struct ProvenanceDateFormatterTests {
    private let enUS = Locale(identifier: "en_US")
    private let esES = Locale(identifier: "es_ES")

    @Test func enUSRendersFriendlyDate() {
        #expect(ProvenanceDateFormatter.friendly("2026-08-01", locale: enUS) == "Aug 1, 2026")
    }

    @Test func esESRendersLocalizedDate() {
        // Spanish abbreviated-date order/spelling: day, abbreviated month, year.
        let result = ProvenanceDateFormatter.friendly("2026-08-01", locale: esES)
        #expect(result.contains("1"))
        #expect(result.lowercased().contains("ago"))  // "ago" = abbreviated "agosto"
        #expect(result.contains("2026"))
    }

    @Test func toleratesATimestampSuffix() {
        // Some payloads may carry a full ISO-8601 instant; only the leading
        // calendar date is meaningful here.
        #expect(ProvenanceDateFormatter.friendly("2026-08-01T00:00:00Z", locale: enUS) == "Aug 1, 2026")
    }

    @Test func unparseableInputFallsBackToRawPrefix() {
        #expect(ProvenanceDateFormatter.friendly("not-a-date", locale: enUS) == "not-a-date")
    }

    /// The regression this type exists to prevent (brewdesk#142): rendering
    /// must not depend on the device/process time zone. Every US zone sits
    /// behind GMT, so a naive `Date(from: "2026-08-01")` parsed at GMT
    /// midnight and then formatted in, say, Pacific time would print
    /// "Jul 31" — one calendar day early. Actually change the process's
    /// system time zone (not just construct a `TimeZone` value — the bug
    /// lives in code that reads `.current`/`.autoupdatingCurrent`, so the
    /// test has to move the thing those read from) and prove the friendly
    /// date still reads Aug 1.
    @Test func doesNotShiftADayInAUSTimeZone() {
        withSystemTimeZone(identifier: "America/Los_Angeles") {
            #expect(ProvenanceDateFormatter.friendly("2026-08-01", locale: enUS) == "Aug 1, 2026")
        }
    }

    @Test func doesNotShiftADayInAnEasternTimeZone() {
        withSystemTimeZone(identifier: "America/New_York") {
            #expect(ProvenanceDateFormatter.friendly("2026-08-01", locale: enUS) == "Aug 1, 2026")
        }
    }

    /// A date right at the year boundary is the sharpest version of the
    /// same bug — a shift-back would also roll over into the wrong year.
    @Test func doesNotShiftAtTheYearBoundary() {
        withSystemTimeZone(identifier: "America/Los_Angeles") {
            #expect(ProvenanceDateFormatter.friendly("2026-01-01", locale: enUS) == "Jan 1, 2026")
        }
    }

    /// Runs `body` with the process's real system time zone changed (via
    /// `TZ` + `tzset` + `NSTimeZone.resetSystemTimeZone()`), then restores
    /// it. Constructing a `TimeZone(identifier:)` value on the side, as an
    /// alternative, wouldn't touch what `.current` / `.autoupdatingCurrent`
    /// actually read — this does.
    private func withSystemTimeZone(identifier: String, _ body: () -> Void) {
        let originalTZ = ProcessInfo.processInfo.environment["TZ"]
        setenv("TZ", identifier, 1)
        tzset()
        NSTimeZone.resetSystemTimeZone()
        defer {
            if let originalTZ {
                setenv("TZ", originalTZ, 1)
            } else {
                unsetenv("TZ")
            }
            tzset()
            NSTimeZone.resetSystemTimeZone()
        }
        body()
    }
}
