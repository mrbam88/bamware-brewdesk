import CoreLocation
import XCTest

/// Replays App Review's first ten minutes as one scripted Release run.
/// Every step asserts on VISIBLE content (never just "didn't crash") and
/// attaches a screenshot, so the xcresult is an evidence archive a human
/// can read without re-running anything. Mirrors the walkthrough in
/// fastlane/review_information/notes.txt and fastlane/metadata/4.3-preflight.md.
///
/// Run on iPhone AND in iPad compatibility (Apple reviewed Baat on an iPad):
///   docs/REVIEWER-SIMULATION.md
final class ReviewerSimulationTests: XCTestCase {
    /// Apple Park. Far outside NYC coverage — the reviewer-in-California case
    /// that emptied the map before brewdesk#1.
    private static let cupertino = CLLocation(latitude: 37.3349, longitude: -122.0090)

    private let englishArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    private let freshInstallArguments = [
        "-brewdesk.onboarding.complete", "NO",
        "-brewdesk.location-intro.complete", "NO",
        "-brewdesk.saved-venue-ids", "",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testReviewerFirstTenMinutes() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)

        // ── 1. Fresh install → onboarding ─────────────────────────────────
        app.launchArguments = englishArguments + freshInstallArguments
        app.launch()

        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 8), "Onboarding did not appear")
        capture("01-onboarding-welcome")
        app.buttons["Continue"].tap()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Every score shows its work."].waitForExistence(timeout: 2))
        capture("02-onboarding-evidence-page")
        app.buttons["Find my work cafe"].tap()

        // ── 2. Decline location → Union Square fallback, full dataset ─────
        XCTAssertTrue(app.staticTexts["Start where you are."].waitForExistence(timeout: 2))
        capture("03-location-intro")
        app.buttons["Use Union Square instead"].tap()
        XCTAssertTrue(app.staticTexts["100 work cafés"].waitForExistence(timeout: 15),
                      "Map did not load the Union Square dataset without location")
        XCTAssertTrue(mapPin(app, named: "Gregorys Coffee").waitForExistence(timeout: 5),
                      "Gregorys Coffee pin missing from the Union Square map")
        capture("04-map-union-square-fallback")

        // ── 3. Browse: list, filters, search ──────────────────────────────
        app.tabBars.buttons["Nearby"].tap()
        XCTAssertTrue(app.navigationBars["Nearby"].waitForExistence(timeout: 5))
        XCTAssertTrue(venueRows(app).firstMatch.waitForExistence(timeout: 15),
                      "Nearby list rendered no venue rows")
        XCTAssertTrue(app.descendants(matching: .any)["dataset-stat-strip"].waitForExistence(timeout: 10),
                      "Dataset stat strip missing from list (brewdesk#34 regression)")
        capture("05-list-nearby")

        app.buttons["Filters"].tap()
        let laptopOnly = app.descendants(matching: .any)["Laptop-friendly only"]
        XCTAssertTrue(laptopOnly.waitForExistence(timeout: 2))
        capture("06-filters-menu")
        laptopOnly.tap()
        XCTAssertTrue(venueRows(app).firstMatch.waitForExistence(timeout: 10),
                      "Laptop-friendly filter produced no venues")
        capture("07-list-laptop-friendly")

        app.tabBars.buttons["Explore"].tap()
        let search = app.textFields["Search cafes"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Housing Works")
        app.keyboards.buttons["Search"].tap()
        XCTAssertTrue(app.staticTexts["1 work café"].waitForExistence(timeout: 15),
                      "Search for Housing Works did not narrow to one venue")
        capture("08-map-search-result")

        // ── 4. Detail: claim-level evidence (the 4.3(b) differentiator) ───
        app.tabBars.buttons["Nearby"].tap()
        let housingWorks = app.staticTexts["Housing Works Bookstore Cafe"].firstMatch
        XCTAssertTrue(housingWorks.waitForExistence(timeout: 5))
        housingWorks.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Workability"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Directions"].exists)
        XCTAssertTrue(app.buttons["Save"].exists)
        XCTAssertTrue(app.buttons["Share"].exists)
        capture("09-detail-evidence")
        app.navigationBars["Details"].buttons.firstMatch.tap()

        // ── 5. Methodology screen ─────────────────────────────────────────
        XCTAssertTrue(app.navigationBars["Nearby"].waitForExistence(timeout: 3))
        app.buttons["How scoring works"].tap()
        XCTAssertTrue(app.navigationBars["How Work Fit works"].waitForExistence(timeout: 3),
                      "Methodology screen did not open from the Nearby toolbar")
        capture("10-methodology")

        // ── 6. Grant location from Cupertino → real viewport query ────────
        // bd#108 removed the client-side "outside NYC" fallback: the app now
        // always queries the real coordinate it was given, so this step no
        // longer forces the NYC dataset or the (removed) "outside NYC"
        // banner. Against the LIVE production engine (this test, no
        // `-UITestScenario`), Cupertino still resolves to the NYC dataset
        // today — the production engine currently has no OSM baseline data
        // and answers a Cupertino-radius query with the same top venues it
        // always has (coverage is absent on pre-ve#46 responses, which
        // `VenuesModel` treats as `.researched`, so no banner is expected
        // here either). Once ve#46 ships, this assertion should be revisited
        // — see `testReviewerCupertinoSeesBaselineCoverageOnFixture` below
        // for the deterministic, fixture-driven proof of the new behaviour
        // that doesn't depend on live production data.
        XCUIDevice.shared.location = XCUILocation(location: Self.cupertino)
        app.terminate()
        app.launchArguments = englishArguments + ["-brewdesk.location-intro.complete", "NO"]
        app.launch()

        XCTAssertTrue(app.buttons["Use my location"].waitForExistence(timeout: 8),
                      "Location intro did not reappear for the grant pass")
        app.buttons["Use my location"].tap()
        allowLocationIfPrompted(app)

        XCTAssertFalse(app.descendants(matching: .any)["coverage-banner"].waitForExistence(timeout: 3),
                       "No coverage banner expected until ve#46 ships coverage for Cupertino")
        XCTAssertTrue(app.staticTexts["100 work cafés"].waitForExistence(timeout: 15),
                      "Map emptied for a Cupertino reviewer (brewdesk#1 regression)")
        XCTAssertTrue(mapPin(app, named: "Gregorys Coffee").waitForExistence(timeout: 5),
                      "Gregorys Coffee pin missing from the map")
        capture("11-map-cupertino-real-viewport")

        // ── 7. Offline mid-browse → relaunch ──────────────────────────────
        // Lands with brewdesk#27's Release-safe fixture seam
        // (`-UITestScenario offline`, ids `map-state-error` / `map-retry`).
        // Until then this step is intentionally absent, not silently passing.

        // ── 8. Relaunch: gates persisted, straight to discovery ───────────
        app.terminate()
        app.launchArguments = englishArguments
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout: 8),
                      "Relaunch replayed onboarding instead of restoring discovery")
        XCTAssertFalse(app.buttons["Continue"].exists)
        XCTAssertTrue(app.staticTexts["100 work cafés"].waitForExistence(timeout: 15))
        capture("12-relaunch-restored")
    }

    /// bd#108, deterministic half of the Cupertino step: once ve#46 ships an
    /// OSM tier-0 baseline, a reviewer whose viewport falls in it sees real
    /// local venues plus the honest baseline banner — never NYC's, never the
    /// (removed) "outside NYC" copy. Runs against the `baselineCity` fixture
    /// rather than live production, which has no OSM baseline data yet;
    /// `testReviewerFirstTenMinutes` above keeps proving the live run still
    /// passes in the meantime.
    @MainActor
    func testReviewerCupertinoSeesBaselineCoverageOnFixture() throws {
        let app = XCUIApplication()
        app.launchArguments = englishArguments + [
            "-UITestScenario", "baselineCity",
            "-UITestSkipGates",
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout: 8))
        let banner = app.descendants(matching: .any)["coverage-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 15),
                      "Baseline coverage banner missing for the baselineCity fixture")
        XCTAssertTrue(app.staticTexts["Baseline data here — not yet researched. NYC is fully researched."].exists)

        app.tabBars.buttons["Nearby"].tap()
        XCTAssertTrue(app.navigationBars["Nearby"].waitForExistence(timeout: 5))
        let rows = venueRows(app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15),
                      "baselineCity fixture rendered no venue rows")
        XCTAssertGreaterThanOrEqual(rows.count, 5, "Expected at least 5 baseline venue rows near Cupertino")
        capture("cupertino-baseline-coverage-fixture")
    }

    // MARK: - Helpers

    /// Map pins expose themselves as buttons labelled
    /// "<name>, Work Fit <score>, <neighborhood>" (CafeMapScreen).
    @MainActor
    private func mapPin(_ app: XCUIApplication, named name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
    }

    /// The location prompt is a system alert owned by SpringBoard; the app
    /// advances to discovery underneath it. Allow it explicitly, then nudge
    /// the app so an interruption monitor catches any late-arriving alert.
    @MainActor
    private func allowLocationIfPrompted(_ app: XCUIApplication) {
        let monitor = addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            for title in ["Allow While Using App", "Allow Once", "Allow"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        defer { removeUIInterruptionMonitor(monitor) }

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 10) {
            allow.tap()
        }
        // Harmless interaction: triggers the monitor if an alert is still up.
        if app.tabBars.buttons["Explore"].waitForExistence(timeout: 8) {
            app.tabBars.buttons["Explore"].tap()
        }
    }

    /// Nearby rows are combined accessibility elements labelled
    /// "<name>, Work Fit <score>, <neighborhood>, Wi-Fi <value>, outlets <value>".
    /// The list is ranked, so never assume a specific café is on screen.
    @MainActor
    private func venueRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", Wi-Fi "))
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
