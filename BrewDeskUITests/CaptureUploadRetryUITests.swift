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
    func testFailedUploadShowsErrorKeepsPhotosAndRetrySucceeds() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", "fixtureOK",
            "-UITestCaptureFailures", "1",
        ]
        app.launch()

        // To the guide, same route as CaptureFlowUITests. brewdesk#170:
        // `staticTexts["Fixture Roasters"]` matched an off-screen duplicate
        // AX node, a stale holdover from before brewdesk#117's map+shelf
        // Spots tab — `mapPin(named:)` is the current, on-screen-aware way
        // every other suite opens a fixture venue.
        let pin = app.mapPin(named: "Fixture Roasters")
        XCTAssertTrue(pin.waitForExistence(timeout: 8), "Fixture venue pin should appear")
        pin.tap()
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: 8))
        // brewdesk#170: capture entry is #if DEBUG-only (VenueDetailScreen);
        // not present in a Release build — see CaptureFlowUITests.
        let entry = app.buttons["capture-entry"]
        guard entry.waitForExistence(timeout: 4) else {
            throw XCTSkip("Capture flow entry point is #if DEBUG-only (VenueDetailScreen); not present in a Release build.")
        }
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
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: 4))
    }
}
