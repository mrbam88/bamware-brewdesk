import Foundation
import Testing
@testable import BrewDeskKit

/// The trigger rule for the feature-flagged (default OFF) gap-fill: "fewer
/// than N of our own pins in the visible region" (bd#182 ticket text,
/// N = `minimumPinsBeforeGapFill`). Network fetch itself
/// (`AppleGapFillService.fetch`) needs a live `MKLocalSearch` and isn't
/// covered here — this pins the pure trigger math only.
@Suite struct AppleGapFillServiceTests {
    @Test func fewerThanMinimumTriggersGapFill() {
        #expect(AppleGapFillService.shouldGapFill(ourPinCount: 0))
        #expect(AppleGapFillService.shouldGapFill(ourPinCount: 4))
    }

    @Test func atOrAboveMinimumDoesNotTrigger() {
        #expect(AppleGapFillService.shouldGapFill(ourPinCount: 5) == false)
        #expect(AppleGapFillService.shouldGapFill(ourPinCount: 20) == false)
    }

    @Test func minimumMatchesTicketSpecifiedFive() {
        #expect(AppleGapFillService.minimumPinsBeforeGapFill == 5)
    }
}
