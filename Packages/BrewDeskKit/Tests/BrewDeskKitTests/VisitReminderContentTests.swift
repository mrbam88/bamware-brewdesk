// Push Phase A (brewdesk#93) — pure content/identifier seams, no
// UNUserNotificationCenter involved.
import Foundation
import Testing
@testable import BrewDeskKit

@Suite struct VisitReminderContentTests {
    @Test func titleInterpolatesVenueName() {
        #expect(VisitReminderContent.title(venueName: "Fixture Roasters") == "How was Fixture Roasters?")
    }

    @Test func bodyIsUtilityCopyNotMarketing() {
        #expect(VisitReminderContent.body == "Rate your visit to help other remote workers.")
    }

    @Test func contentCarriesVenueIdForTheDeepLink() {
        let content = VisitReminderContent.makeContent(venueId: "v1", venueName: "Fixture Roasters")
        #expect(content.userInfo[VisitReminderContent.venueIdKey] as? String == "v1")
        #expect(content.title == "How was Fixture Roasters?")
        #expect(content.body == "Rate your visit to help other remote workers.")
    }

    @Test func requestIdentifierIsStablePerVenue() {
        #expect(UserNotificationVisitReminders.identifier(for: "v1") == UserNotificationVisitReminders.identifier(for: "v1"))
        #expect(UserNotificationVisitReminders.identifier(for: "v1") != UserNotificationVisitReminders.identifier(for: "v2"))
    }
}
