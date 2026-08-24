import XCTest

/// Deterministic screen-by-screen capture for the round-2 UI review (#75).
/// Walks onboarding -> map/shelf -> detail -> rate-visit -> saved -> import
/// -> methodology against the `fixtureOK` scenario (no live API, no network
/// flakiness) and attaches one named screenshot per screen.
///
/// brewdesk#117 (UI3 tab restructure): detail now opens from the Spots
/// map/shelf as a sheet (no more Nearby-list push with a real back button —
/// Nearby is gone), so this walkthrough dismisses it with a swipe instead
/// of a nav-bar back button, and Methodology is reached from the You tab
/// instead of the (removed) Nearby toolbar.
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
        app.buttons["Find my work spot"].tap()

        // ── 2. Location intro ───────────────────────────────────────────
        XCTAssertTrue(app.staticTexts["Start where you are."].waitForExistence(timeout: 3))
        capture(app, "03-location-intro")
        app.buttons["Use Union Square instead"].tap()

        // ── 3. Map + shelf ──────────────────────────────────────────────
        XCTAssertTrue(app.descendants(matching: .any)["map-discovery-shelf"].waitForExistence(timeout: 15))
        capture(app, "04-map-shelf")

        // ── 4. Venue detail (a sheet from the Spots map/shelf) ──────────
        let pin = app.mapPin(named: "Fixture Roasters")
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        pin.tap()
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Workability"].waitForExistence(timeout: 3))
        capture(app, "05-venue-detail")

        // ── 5. Rate this visit ──────────────────────────────────────────
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
        capture(app, "06-rate-this-visit")
        let cancel = app.buttons.matching(identifier: "observation-cancel").firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        cancel.tap()

        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: 10))
        // Sheet, not a push (brewdesk#117) — swipe down to dismiss back to Spots.
        app.dismissDetailSheet()
        XCTAssertTrue(app.descendants(matching: .any)["map-discovery-shelf"].waitForExistence(timeout: 10))

        // ── 6. Saved (empty state — launched with no saved ids) ────────
        let savedTab = app.tabBars.buttons["tab-saved"]
        XCTAssertTrue(savedTab.waitForExistence(timeout: 5))
        savedTab.waitUntilHittable()
        savedTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["saved-state-empty"].waitForExistence(timeout: 5))
        capture(app, "07-saved-empty")

        // ── 7. Import saved places ──────────────────────────────────────
        let importEntry = app.descendants(matching: .any)["import-saved-entry"]
        XCTAssertTrue(importEntry.waitForExistence(timeout: 5))
        importEntry.tap()
        XCTAssertTrue(app.navigationBars["Import saved places"].waitForExistence(timeout: 5))
        capture(app, "08-import-saved")
        app.navigationBars["Import saved places"].buttons.firstMatch.tap()

        // ── 8. Methodology (reached from the You tab — Nearby's toolbar
        // entry is gone with the tab) ────────────────────────────────────
        XCTAssertTrue(app.tabBars.buttons["tab-you"].waitForExistence(timeout: 5))
        app.tabBars.buttons["tab-you"].tap()
        app.descendants(matching: .any)["methodology-link"].tap()
        XCTAssertTrue(app.navigationBars["How Work Fit works"].waitForExistence(timeout: 5))
        capture(app, "09-methodology")
    }

    // MARK: - Helpers

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(name)-\(isDark ? "dark" : "light")"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
