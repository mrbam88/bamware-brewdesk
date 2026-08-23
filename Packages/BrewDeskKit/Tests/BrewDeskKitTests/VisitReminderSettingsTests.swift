// Push Phase A (brewdesk#93) — scheduler tests: fixed clock via the
// `now:` parameter, fake `UNUserNotificationCenter` stand-in
// (`FakeVisitReminders`), never touching real UserDefaults or the system
// notification center.
import Foundation
import Testing
@testable import BrewDeskKit

@MainActor
private final class MemoryVisitReminderPreferences: VisitReminderPreferencesPersisting {
    var enabled: Bool
    private(set) var saveCallCount = 0

    init(enabled: Bool = false) {
        self.enabled = enabled
    }

    func loadEnabled() -> Bool { enabled }

    func saveEnabled(_ enabled: Bool) {
        self.enabled = enabled
        saveCallCount += 1
    }
}

@Suite @MainActor struct VisitReminderSettingsTests {
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Directions tap → scheduling

    @Test func directionsTapSchedulesTwoHoursOutWhenAlreadyEnabled() async throws {
        let reminders = FakeVisitReminders()
        let settings = VisitReminderSettings(
            reminders: reminders,
            persistence: MemoryVisitReminderPreferences(enabled: true)
        )

        await settings.directionsTapped(venueId: "v1", name: "Fixture Roasters", now: fixedNow)

        #expect(reminders.scheduled.count == 1)
        let reminder = try #require(reminders.scheduled.first)
        #expect(reminder.venueId == "v1")
        #expect(reminder.name == "Fixture Roasters")
        #expect(reminder.at == fixedNow.addingTimeInterval(2 * 60 * 60))
        // Already enabled — the inline prompt never appears.
        #expect(settings.promptTarget == nil)
    }

    @Test func directionsTapDoesNotScheduleWhenDisabled() async {
        let reminders = FakeVisitReminders()
        let settings = VisitReminderSettings(reminders: reminders, persistence: MemoryVisitReminderPreferences())

        await settings.directionsTapped(venueId: "v1", name: "Fixture Roasters", now: fixedNow)

        #expect(reminders.scheduled.isEmpty)
        #expect(settings.promptTarget?.venueId == "v1")
    }

    @Test func directionsTapPromptsOnlyOncePerSession() async {
        let reminders = FakeVisitReminders()
        let settings = VisitReminderSettings(reminders: reminders, persistence: MemoryVisitReminderPreferences())

        await settings.directionsTapped(venueId: "v1", name: "First", now: fixedNow)
        #expect(settings.promptTarget?.venueId == "v1")

        settings.declinePrompt()
        #expect(settings.promptTarget == nil)

        // A second Directions tap (even on a different venue) must not
        // prompt again this session.
        await settings.directionsTapped(venueId: "v2", name: "Second", now: fixedNow)
        #expect(settings.promptTarget == nil)
        #expect(reminders.scheduled.isEmpty)
    }

    // MARK: - Inline prompt "Yes"

    @Test func acceptPromptRequestsAuthorizationThenSchedules() async {
        let reminders = FakeVisitReminders()
        reminders.authorizationGrantResult = true
        let persistence = MemoryVisitReminderPreferences()
        let settings = VisitReminderSettings(reminders: reminders, persistence: persistence)

        await settings.directionsTapped(venueId: "v1", name: "Fixture Roasters", now: fixedNow)
        await settings.acceptPrompt(now: fixedNow)

        #expect(settings.isEnabled)
        #expect(persistence.enabled)
        #expect(reminders.scheduled.count == 1)
        #expect(reminders.scheduled.first?.at == fixedNow.addingTimeInterval(2 * 60 * 60))
    }

    @Test func acceptPromptDeniedLeavesReemindersOffAndUnscheduled() async {
        let reminders = FakeVisitReminders()
        reminders.authorizationGrantResult = false
        let settings = VisitReminderSettings(reminders: reminders, persistence: MemoryVisitReminderPreferences())

        await settings.directionsTapped(venueId: "v1", name: "Fixture Roasters", now: fixedNow)
        await settings.acceptPrompt(now: fixedNow)

        #expect(!settings.isEnabled)
        #expect(settings.authorizationStatus == .denied)
        #expect(reminders.scheduled.isEmpty)
    }

    // MARK: - Saved toggle

    @Test func toggleOffCancelsAllPending() async {
        let reminders = FakeVisitReminders()
        let persistence = MemoryVisitReminderPreferences(enabled: true)
        let settings = VisitReminderSettings(reminders: reminders, persistence: persistence)
        await settings.directionsTapped(venueId: "v1", name: "Fixture Roasters", now: fixedNow)
        #expect(reminders.scheduled.count == 1)

        await settings.setEnabled(false)

        #expect(!settings.isEnabled)
        #expect(!persistence.enabled)
        #expect(reminders.cancelAllCallCount == 1)
        let pending = await settings.pendingCount
        #expect(pending == 0)
    }

    @Test func toggleOnGrantedEnablesAndPersists() async {
        let reminders = FakeVisitReminders()
        reminders.authorizationGrantResult = true
        let persistence = MemoryVisitReminderPreferences()
        let settings = VisitReminderSettings(reminders: reminders, persistence: persistence)

        await settings.setEnabled(true)

        #expect(settings.isEnabled)
        #expect(persistence.enabled)
        #expect(persistence.saveCallCount == 1)
    }

    @Test func reschedulingSameVenueReplacesRatherThanDuplicating() async {
        let reminders = FakeVisitReminders()
        let settings = VisitReminderSettings(
            reminders: reminders,
            persistence: MemoryVisitReminderPreferences(enabled: true)
        )

        await settings.directionsTapped(venueId: "v1", name: "First", now: fixedNow)
        await settings.directionsTapped(venueId: "v1", name: "First", now: fixedNow.addingTimeInterval(60))

        #expect(reminders.scheduled.count == 1)
        #expect(reminders.scheduled.first?.at == fixedNow.addingTimeInterval(60 + 2 * 60 * 60))
    }

    @Test func startsDisabledByDefault() {
        let settings = VisitReminderSettings(reminders: FakeVisitReminders(), persistence: MemoryVisitReminderPreferences())
        #expect(!settings.isEnabled)
    }
}
