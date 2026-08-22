import XCTest

/// Structured observation form (brewdesk#47, #79): the "Rate this visit" entry on
/// the venue detail, the five one-tap questions, submit → thank-you, and the
/// engine-down friendly error + Retry. Fixture-driven via `-UITestScenario`
/// (see `ScenarioVenueService`) so every state is deterministic — no live API.
final class ObservationFormUITests: XCTestCase {
    private let wait: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launch(_ scenario: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", scenario,
            "-brewdesk.saved-venue-ids", "()",
        ] + extra
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func openNearby(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Nearby"].waitForExistence(timeout: wait))
        app.tabBars.buttons["Nearby"].tap()
    }

    @MainActor
    private func openFixtureRoastersDetail(_ app: XCUIApplication) {
        openNearby(app)
        let row = app.staticTexts["Fixture Roasters"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: wait))
        row.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: wait))
    }

    /// The entry card sits at the bottom of the detail scroll view; swipe
    /// until it is hittable (the number of swipes depends on Dynamic Type).
    @MainActor
    private func openObservationForm(_ app: XCUIApplication) {
        let entry = element(app, "observation-entry")
        var swipes = 0
        while !(entry.exists && entry.isHittable), swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(entry.isHittable, "Rate this visit entry not reachable on the detail screen")
        entry.tap()
        XCTAssertTrue(app.navigationBars["Rate this visit"].waitForExistence(timeout: wait))
    }

    /// One tap per question — the whole point of the structured form. The
    /// Wi-Fi row (brewdesk#79) is answered LAST so `answerAllButWifi` can
    /// reuse the first four taps for the gating assertion.
    @MainActor
    private func answerAllFive(_ app: XCUIApplication) {
        answerAllButWifi(app)
        tapOption(app, "observation-wifi-acceptable")
    }

    @MainActor
    private func answerAllButWifi(_ app: XCUIApplication) {
        for identifier in [
            "observation-laptop-yes",
            "observation-seats-plenty",
            "observation-outlets-few",
            "observation-noise-quiet",
        ] {
            tapOption(app, identifier)
        }
    }

    @MainActor
    private func tapOption(_ app: XCUIApplication, _ identifier: String) {
        let option = element(app, identifier)
        // Five cards can push the last one off-screen on smaller type sizes.
        if !option.exists || !option.isHittable { app.swipeUp() }
        XCTAssertTrue(option.waitForExistence(timeout: wait), "missing option \(identifier)")
        option.tap()
    }

    // MARK: - Happy path

    @MainActor
    func testHappyPathFiveTapsSubmitThanksAndDone() {
        let app = launch("fixtureOK")
        openFixtureRoastersDetail(app)
        openObservationForm(app)

        // Submit is gated until all five questions are answered.
        let submit = element(app, "observation-submit")
        XCTAssertTrue(submit.waitForExistence(timeout: wait))
        XCTAssertFalse(submit.isEnabled, "Submit must stay disabled until all five answers are in")

        // brewdesk#79: the four original answers alone must NOT enable Submit.
        answerAllButWifi(app)
        XCTAssertFalse(submit.isEnabled, "Submit must stay disabled until the Wi-Fi question is answered")

        tapOption(app, "observation-wifi-acceptable")
        XCTAssertTrue(submit.isEnabled)
        submit.tap()

        XCTAssertTrue(element(app, "observation-thanks").waitForExistence(timeout: wait),
                      "Thank-you state missing after submit")
        element(app, "observation-done").tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: wait),
                      "Done should land back on the venue detail")
    }

    // MARK: - Engine down

    /// Engine 500 on submit: a friendly error with Retry, answers intact,
    /// never a crash or a silent dismissal. Snapshot-seeded so the detail
    /// screen is reachable while every engine call fails.
    @MainActor
    func testEngineDownShowsFriendlyErrorWithRetry() {
        let app = launch("engineDown", extra: ["-UITestSeedSnapshot"])
        openNearby(app)
        guard let (row, _) = app.firstVenueRow(timeout: wait) else {
            return XCTFail("No snapshot venue row to open")
        }
        row.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: wait))
        openObservationForm(app)

        answerAllFive(app)
        element(app, "observation-submit").tap()

        XCTAssertTrue(element(app, "observation-error").waitForExistence(timeout: wait),
                      "Friendly error banner missing while the engine is down")
        let retry = element(app, "observation-retry")
        XCTAssertTrue(retry.exists)

        // Retry against a still-down engine: the same friendly state, calmly.
        retry.tap()
        XCTAssertTrue(element(app, "observation-error").waitForExistence(timeout: wait),
                      "Error banner must persist when retry fails again")
        XCTAssertTrue(element(app, "observation-retry").exists)

        // The form is still alive and editable — answers were not lost.
        XCTAssertTrue(element(app, "observation-laptop-yes").exists)
    }

    // MARK: - Accessibility audit (brewdesk#47 AC)

    @MainActor
    func testObservationFormPassesAccessibilityAudit() throws {
        let app = launch("fixtureOK")
        openFixtureRoastersDetail(app)
        openObservationForm(app)
        // Audit the form in its gated state (Submit disabled), then answered.
        try audit(app)
        answerAllFive(app)
        try audit(app)
    }

    /// Same audit set as CaptureFlowUITests, but contrast runs in its own
    /// pass: a combined multi-type audit delivers contrast issues with
    /// `issue.element == nil` (verified on the 17e runs for brewdesk#47),
    /// which makes the WCAG 1.4.3 inactive-control exemption impossible to
    /// apply. Audited alone, the same issue carries its element.
    @MainActor
    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: .contrast) { issue in
            // WCAG 1.4.3 exempts inactive controls from contrast minimums;
            // the audit flags the system-dimmed disabled "Send" anyway.
            issue.element?.isEnabled == false
        }
        try app.performAccessibilityAudit(
            for: [.dynamicType, .hitRegion, .sufficientElementDescription,
                  .textClipped, .trait]
        ) { issue in
            // Bar buttons ("Cancel") sit in system chrome whose type ramp the
            // audit misjudges — same exemption CaptureFlowUITests carries.
            issue.auditType == .dynamicType && issue.element?.label == "Cancel"
        }
    }
}
