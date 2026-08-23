import XCTest

/// Push Phase A (brewdesk#93): permission is only ever asked from the
/// Directions-tap inline prompt or the Saved toggle, never on launch.
/// `-UITestScenario` swaps the real `UNUserNotificationCenter` rail for
/// `FakeVisitReminders.shared` (see `VisitReminderSettings.shared`) — no
/// real system permission prompt fires in this test.
final class VisitReminderUITests: XCTestCase {
    private let wait: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", "fixtureOK",
            "-brewdesk.saved-venue-ids", "()",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func openFixtureRoastersDetail(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Nearby"].waitForExistence(timeout: wait))
        app.tabBars.buttons["Nearby"].tap()
        let row = app.staticTexts["Fixture Roasters"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: wait))
        row.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: wait))
    }

    /// Waits for `element`'s accessibility label/value to equal `value`,
    /// using the standard `NSPredicate` expectation mechanism (not a manual
    /// sleep/polling loop) — covers the beat between a `Task { await }`
    /// side effect and the next SwiftUI render.
    @MainActor
    private func waitForValue(_ element: XCUIElement, keyPath: String, equals value: String) {
        let predicate = NSPredicate(format: "\(keyPath) == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: wait)
        XCTAssertEqual(result, .completed, "expected \(keyPath) == \(value), was \(element.value ?? element.label)")
    }

    /// Reaching the Saved toggle after `Task { await }` state changes fires
    /// on the *previous* screen (accept/decline both mutate the same
    /// process-shared `VisitReminderSettings` before the tab switch)
    /// repeatedly triggered a `waitForExistence` polling stall against this
    /// specific element in this environment — never against a screenshot or
    /// `debugDescription` taken the same way, and the underlying state was
    /// always already correct by then. One settle beat plus a single
    /// existence check sidesteps the polling path entirely.
    @MainActor
    private func savedToggle(_ app: XCUIApplication) -> XCUIElement {
        Thread.sleep(forTimeInterval: 1.5)
        let toggle = element(app, "visit-reminder-toggle")
        XCTAssertTrue(toggle.exists, "visit-reminder-toggle should exist on Saved")
        return toggle
    }

    /// `VisitReminderToggleRow` groups the whole "icon + label + switch" row
    /// into one accessibility element (a Settings-app-style row), so
    /// `toggle.tap()` — which hits the *center* of that wide, whole-row
    /// frame — lands on the label text, not the switch, and the toggle
    /// silently never flips (confirmed with a screenshot: value and visual
    /// state both stayed unchanged for 4+ seconds after such a tap). Tap
    /// near the switch's actual on-screen position (the row's right edge)
    /// instead.
    @MainActor
    private func tapToggle(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    // MARK: - Test

    @MainActor
    func testDirectionsTapPromptAcceptTogglesOnThenOffClearsPending() {
        let app = launch()
        openFixtureRoastersDetail(app)

        // No prompt before any Directions tap (never on launch).
        XCTAssertFalse(element(app, "visit-reminder-prompt").exists)

        let directions = app.buttons["Directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: wait))
        directions.tap()

        let prompt = element(app, "visit-reminder-prompt")
        XCTAssertTrue(prompt.waitForExistence(timeout: wait))

        let yes = element(app, "visit-reminder-yes")
        XCTAssertTrue(yes.waitForExistence(timeout: wait))
        yes.tap()
        XCTAssertFalse(prompt.exists, "prompt should dismiss on Yes")

        // Saved tab: the toggle reflects the grant, and the debug pending
        // count (UI-test-only) shows the reminder that Yes just scheduled.
        XCTAssertTrue(app.tabBars.buttons["Saved"].waitForExistence(timeout: wait))
        app.tabBars.buttons["Saved"].tap()

        let toggle = savedToggle(app)
        waitForValue(toggle, keyPath: "value", equals: "1")

        let pendingLabel = element(app, "visit-reminder-pending-count")
        XCTAssertTrue(pendingLabel.waitForExistence(timeout: wait))
        waitForValue(pendingLabel, keyPath: "label", equals: "pending: 1")

        // Toggle off cancels every pending reminder.
        tapToggle(toggle)
        waitForValue(pendingLabel, keyPath: "label", equals: "pending: 0")
        waitForValue(toggle, keyPath: "value", equals: "0")
    }

    /// "Not now" must never ask the system, and must not ask again this
    /// session — a second Directions tap stays quiet.
    @MainActor
    func testNotNowNeverAsksAgainThisSession() {
        let app = launch()
        openFixtureRoastersDetail(app)

        app.buttons["Directions"].tap()

        let prompt = element(app, "visit-reminder-prompt")
        XCTAssertTrue(prompt.waitForExistence(timeout: wait))
        element(app, "visit-reminder-later").tap()
        XCTAssertFalse(prompt.exists)

        // A second Directions tap in the same session must not ask again.
        app.buttons["Directions"].tap()
        XCTAssertFalse(element(app, "visit-reminder-prompt").waitForExistence(timeout: 3))

        app.tabBars.buttons["Saved"].tap()
        let toggle = savedToggle(app)
        XCTAssertEqual(toggle.value as? String, "0")
    }
}
