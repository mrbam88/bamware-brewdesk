// Community capture prototype UI tests (brewdesk#46).
// Walks the guided flow through all four states (guide → shoot → confirm →
// submitted) on the fixture scenario, and runs the accessibility audit on
// each state. The flow is Debug-only, so this suite is meaningful in Debug —
// the standard local test configuration.
import XCTest

final class CaptureFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Launch on fixtures → Fixture Roasters detail → capture entry → guide.
    @MainActor
    private func launchToCaptureGuide() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipGates", "-UITestScenario", "fixtureOK"]
        app.launch()

        let row = app.staticTexts["Fixture Roasters"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Fixture venue row should appear")
        row.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 8))

        let entry = app.buttons["capture-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 4), "DEBUG capture entry should be in the toolbar")
        entry.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["capture-guide"].waitForExistence(timeout: 4),
            "Guide state should present"
        )
        return app
    }

    @MainActor
    private func shootSamplePhotoAndAdvance(_ app: XCUIApplication, expectedStep: Int) {
        XCTAssertTrue(
            app.staticTexts["Shot \(expectedStep) of 3"].waitForExistence(timeout: 4),
            "Progress header should read Shot \(expectedStep) of 3"
        )
        let next = app.buttons["capture-next"]
        XCTAssertFalse(next.isEnabled, "Next is disabled until this step has a photo")
        app.buttons["capture-photo-sample"].tap()
        XCTAssertTrue(next.isEnabled, "Instant feedback: photo enables Next")
        next.tap()
    }

    @MainActor
    func testCaptureFlowWalksAllFourStates() {
        let app = launchToCaptureGuide()

        // guide → shoot
        app.buttons["capture-start"].tap()

        // shoot 1 and 2 with sample photos; skip 3 (the honest-skip path)
        shootSamplePhotoAndAdvance(app, expectedStep: 1)
        shootSamplePhotoAndAdvance(app, expectedStep: 2)
        XCTAssertTrue(app.staticTexts["Shot 3 of 3"].waitForExistence(timeout: 4))
        app.buttons["capture-skip"].tap()

        // confirm: three slots, skipped slot visible, then submit
        XCTAssertTrue(app.descendants(matching: .any)["capture-confirm"].waitForExistence(timeout: 4))
        let outletsSlot = app.descendants(matching: .any)["capture-slot-outlets"]
        XCTAssertTrue(outletsSlot.exists)
        XCTAssertTrue(
            outletsSlot.label.contains("Skipped"),
            "Skipped slot is marked honestly on Confirm"
        )
        app.buttons["capture-submit"].tap()

        // submitted → done returns to the venue detail
        XCTAssertTrue(
            app.descendants(matching: .any)["capture-submitted"].waitForExistence(timeout: 8),
            "Mock submission should land on the thank-you state"
        )
        app.buttons["capture-done"].tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 4))
    }

    @MainActor
    func testCancelWithPhotosAsksBeforeDiscarding() {
        let app = launchToCaptureGuide()
        app.buttons["capture-start"].tap()
        XCTAssertTrue(app.staticTexts["Shot 1 of 3"].waitForExistence(timeout: 4))
        app.buttons["capture-photo-sample"].tap()

        app.buttons["capture-cancel"].tap()
        let alert = app.alerts["Discard your photos?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 4), "Cancel with photos must confirm first")
        alert.buttons["Keep going"].tap()
        XCTAssertTrue(app.staticTexts["Shot 1 of 3"].exists, "Keep going stays on the shot")

        app.buttons["capture-cancel"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 4))
        alert.buttons["Discard"].tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 4))
    }

    /// Audit scoped like the Details-screen audit in BrewDeskUITests (same
    /// type list plus `.dynamicType`), with two targeted ignores, both
    /// verified against real audit runs on iPhone 17e:
    /// - Navigation-bar buttons never scale with Dynamic Type (iOS shows
    ///   them in the large content viewer instead), so the sheet's toolbar
    ///   Cancel is exempt from that one check.
    /// - `.elementDetection` is excluded: it OCRs the whole screen, so the
    ///   map labels and the DEBUG "ENV: Localhost" badge peeking out above
    ///   the sheet fail it — content behind the capture flow, not part of
    ///   it. The reported issue carries no element, so it cannot be filtered
    ///   by frame; under a sheet this audit type is structurally unusable.
    ///   Every capture screen is built from plain SwiftUI Text/Button/Label,
    ///   which the accessibility API exposes by construction.
    @MainActor
    private func auditCaptureState(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: [
            .contrast,
            .dynamicType,
            .hitRegion,
            .sufficientElementDescription,
            .textClipped,
            .trait,
        ]) { issue in
            if issue.auditType == .dynamicType, issue.element?.label == "Cancel" {
                return true
            }
            // WCAG 1.4.3 exempts inactive controls from contrast minimums;
            // the audit flags the system-dimmed disabled "Next" anyway.
            // Ignore contrast only while the element is actually disabled.
            if issue.auditType == .contrast, let element = issue.element,
                !element.isEnabled
            {
                return true
            }
            // The "Shot n of 3" header sits under the sheet nav bar's
            // scroll-edge blur material. The audit cannot resolve text
            // backgrounds under materials and reports a hard fail even for
            // fully opaque #404040-on-oat (≥8:1, verified by hand from the
            // audit's own element screenshot). Exempt exactly that header.
            if issue.auditType == .contrast,
                issue.element?.label.hasPrefix("Shot ") == true
            {
                return true
            }
            return false
        }
    }

    @MainActor
    func testCaptureFlowAccessibilityAuditOnAllFourStates() throws {
        let app = launchToCaptureGuide()
        try auditCaptureState(app)  // guide

        app.buttons["capture-start"].tap()
        XCTAssertTrue(app.staticTexts["Shot 1 of 3"].waitForExistence(timeout: 4))
        try auditCaptureState(app)  // shoot

        shootSamplePhotoAndAdvance(app, expectedStep: 1)
        shootSamplePhotoAndAdvance(app, expectedStep: 2)
        XCTAssertTrue(app.staticTexts["Shot 3 of 3"].waitForExistence(timeout: 4))
        app.buttons["capture-skip"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture-confirm"].waitForExistence(timeout: 4))
        try auditCaptureState(app)  // confirm

        app.buttons["capture-submit"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture-submitted"].waitForExistence(timeout: 8))
        try auditCaptureState(app)  // submitted (no Cancel here; filter is inert)
    }
}
