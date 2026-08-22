// Capture upload-failed → retry UI test (brewdesk#71).
// `-UITestCaptureFailures 1` (see `CaptureSubmissionServiceResolver`)
// scripts the submission service to fail exactly once, pinning the confirm
// screen's error surface and proving Retry succeeds without re-shooting —
// photos are never lost on failure. Fixture-driven, no network; the flow
// is Debug-only so this suite is meaningful in Debug.
import XCTest

final class CaptureUploadRetryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFailedUploadShowsErrorKeepsPhotosAndRetrySucceeds() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", "fixtureOK",
            "-UITestCaptureFailures", "1",
        ]
        app.launch()

        // To the guide, same route as CaptureFlowUITests.
        let row = app.staticTexts["Fixture Roasters"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Fixture venue row should appear")
        row.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 8))
        let entry = app.buttons["capture-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 4), "DEBUG capture entry should be in the toolbar")
        entry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture-guide"].waitForExistence(timeout: 4))

        // Fastest route to Confirm: one sample photo, skip the rest.
        app.buttons["capture-start"].tap()
        XCTAssertTrue(app.staticTexts["Shot 1 of 3"].waitForExistence(timeout: 4))
        app.buttons["capture-photo-sample"].tap()
        app.buttons["capture-next"].tap()
        XCTAssertTrue(app.staticTexts["Shot 2 of 3"].waitForExistence(timeout: 4))
        app.buttons["capture-skip"].tap()
        XCTAssertTrue(app.staticTexts["Shot 3 of 3"].waitForExistence(timeout: 4))
        app.buttons["capture-skip"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture-confirm"].waitForExistence(timeout: 4))

        // First submit fails: error surfaces, flow stays on Confirm.
        let submit = app.buttons["capture-submit"]
        submit.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["capture-error"].waitForExistence(timeout: 8),
            "The scripted failure must surface the error state on Confirm"
        )
        XCTAssertTrue(
            submit.label.contains("Try again"),
            "After a failure the submit button reads Try again"
        )
        let firstSlot = app.descendants(matching: .any)["capture-slot-room-from-door"]
        XCTAssertTrue(firstSlot.exists)
        XCTAssertTrue(
            firstSlot.label.contains("Photo added"),
            "Photos are never lost on failure — the shot survives for the retry"
        )

        // Retry succeeds without re-shooting anything.
        submit.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["capture-submitted"].waitForExistence(timeout: 8),
            "Retry must land on the thank-you state"
        )
        app.buttons["capture-done"].tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 4))
    }
}
