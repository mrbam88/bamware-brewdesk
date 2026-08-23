import XCTest

/// Deterministic screen-by-screen capture for the round-2 UI review (#75).
/// Walks onboarding -> map/shelf -> nearby -> detail -> rate-visit -> saved ->
/// import -> methodology against the `fixtureOK` scenario (no live API, no
/// network flakiness) and attaches one named screenshot per screen. Detail is
/// opened from the Nearby list (a `NavigationLink` push with a real back
/// button) rather than the map shelf's modal `.sheet`, which has no toolbar
/// dismiss control in Release and only drag-dismisses.
///
/// Runs twice — once per appearance — via the `TEST_RUNNER_UIREVIEW_DARK`
/// environment variable (`1` forces `-AppleInterfaceStyle Dark`; unset/`0`
/// captures light). Screenshot names carry a `-light`/`-dark` suffix so both
/// runs export into the same result bundle without colliding.
///
/// Not part of the default gate matrix — run explicitly with
/// `-only-testing:BrewDeskUITests/UIReviewCaptureTests`. See docs/TESTING.md.
final class UIReviewCaptureTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var isDark: Bool {
        ProcessInfo.processInfo.environment["UIREVIEW_DARK"] == "1"
    }

    @MainActor
    func testCaptureEveryScreen() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-brewdesk.onboarding.complete", "NO",
            "-brewdesk.location-intro.complete", "NO",
            "-brewdesk.saved-venue-ids", "()",
            "-UITestScenario", "fixtureOK",
            "-brewdesk.uitest-fixed-now", "2026-08-22T15:00:00Z",
        ]
        if isDark {
            app.launchArguments += ["-UIUserInterfaceStyle", "Dark"]
        }
        app.launch()

        // ── 1. Onboarding ───────────────────────────────────────────────
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 8))
        capture(app, "01-onboarding-welcome")
        app.buttons["Continue"].tap()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Every score shows its work."].waitForExistence(timeout: 3))
        capture(app, "02-onboarding-evidence")
        app.buttons["Find my work cafe"].tap()

        // ── 2. Location intro ───────────────────────────────────────────
        XCTAssertTrue(app.staticTexts["Start where you are."].waitForExistence(timeout: 3))
        capture(app, "03-location-intro")
        app.buttons["Use Union Square instead"].tap()

        // ── 3. Map + shelf ──────────────────────────────────────────────
        XCTAssertTrue(app.descendants(matching: .any)["map-discovery-shelf"].waitForExistence(timeout: 15))
        capture(app, "04-map-shelf")

        // ── 4. Nearby list ──────────────────────────────────────────────
        XCTAssertTrue(app.tabBars.buttons["Nearby"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Nearby"].tap()
        XCTAssertTrue(app.navigationBars["Nearby"].waitForExistence(timeout: 5))
        XCTAssertTrue(venueRows(app).firstMatch.waitForExistence(timeout: 10))
        capture(app, "05-nearby-list")

        // ── 5. Venue detail (pushed — real back button) ─────────────────
        let row = app.staticTexts["Fixture Roasters"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Workability"].waitForExistence(timeout: 3))
        capture(app, "06-venue-detail")

        // ── 6. Rate this visit ──────────────────────────────────────────
        // The entry card sits at the bottom of the detail scroll view; swipe
        // until it is hittable (count depends on Dynamic Type / device).
        let rateEntry = app.descendants(matching: .any)["observation-entry"]
        var swipes = 0
        while !(rateEntry.exists && rateEntry.isHittable), swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(rateEntry.isHittable, "Rate this visit entry not reachable on the detail screen")
        rateEntry.tap()
        XCTAssertTrue(app.navigationBars["Rate this visit"].waitForExistence(timeout: 5))
        capture(app, "07-rate-this-visit")
        let cancel = app.buttons.matching(identifier: "observation-cancel").firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        cancel.tap()

        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 10))
        let detailBack = app.navigationBars["Details"].buttons.firstMatch
        XCTAssertTrue(detailBack.waitForExistence(timeout: 10))
        detailBack.tap()

        // ── 7. Saved (empty state — launched with no saved ids) ────────
        XCTAssertTrue(app.tabBars.buttons["Saved"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["saved-state-empty"].waitForExistence(timeout: 5))
        capture(app, "08-saved-empty")

        // ── 8. Import saved places ──────────────────────────────────────
        let importEntry = app.descendants(matching: .any)["import-saved-entry"]
        XCTAssertTrue(importEntry.waitForExistence(timeout: 5))
        importEntry.tap()
        XCTAssertTrue(app.navigationBars["Import saved places"].waitForExistence(timeout: 5))
        capture(app, "09-import-saved")
        app.navigationBars["Import saved places"].buttons.firstMatch.tap()

        // ── 9. Methodology ──────────────────────────────────────────────
        XCTAssertTrue(app.tabBars.buttons["Nearby"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Nearby"].tap()
        XCTAssertTrue(app.navigationBars["Nearby"].waitForExistence(timeout: 5))
        app.buttons["How scoring works"].tap()
        XCTAssertTrue(app.navigationBars["How Work Fit works"].waitForExistence(timeout: 5))
        capture(app, "10-methodology")
    }

    // MARK: - Helpers

    @MainActor
    private func venueRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", Wi-Fi "))
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(name)-\(isDark ? "dark" : "light")"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
