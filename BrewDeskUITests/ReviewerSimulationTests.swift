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
///
/// brewdesk#117 (UI3 tab restructure): Explore + Nearby collapsed into one
/// Spots tab, and Account became its own You tab. Tab navigation broke, so
/// this suite was updated per the ticket's explicit carve-out. The Filters
/// step (Nearby's list menu) is dropped — UI3: filter surface moves to
/// WorkFitFilterMenu — un-skip in #118 — and the capture numbering was
/// tightened up to match.
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
        app.buttons["Find my work spot"].tap()

        // ── 2. Decline location → Union Square fallback, full dataset ─────
        XCTAssertTrue(app.staticTexts["Start where you are."].waitForExistence(timeout: 2))
        capture("03-location-intro")
        app.buttons["Use Union Square instead"].tap()
        XCTAssertTrue(app.staticTexts["100 work spots"].waitForExistence(timeout: 15),
                      "Map did not load the Union Square dataset without location")
        // brewdesk#37 rule: live data re-ranks/renames venues, so match the
        // pin shape, not a café name (the matcher merge of 2026-08-23 renamed
        // "Gregorys Coffee" to its OSM record "Gregory's coffee").
        XCTAssertTrue(app.mapPins.firstMatch.waitForExistence(timeout: 5),
                      "No venue pins on the Union Square map")
        capture("04-map-union-square-fallback")

        // ── 3. Browse: one Spots surface now (map + shelf), then search ───
        // brewdesk#117 collapsed Explore + Nearby into Spots, so there's no
        // second tab to switch to for this step any more.
        XCTAssertTrue(app.descendants(matching: .any)["dataset-stat-strip"].waitForExistence(timeout: 10),
                      "Dataset stat strip missing from Spots (brewdesk#34 regression)")
        capture("05-map-spots-browse")

        let search = app.textFields["Search spots"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Housing Works")
        app.keyboards.buttons["Search"].tap()
        XCTAssertTrue(app.staticTexts["1 work spot"].waitForExistence(timeout: 15),
                      "Search for Housing Works did not narrow to one venue")
        capture("06-map-search-result")

        // ── 4. Detail: claim-level evidence (the 4.3(b) differentiator) ───
        let housingWorks = app.mapPin(named: "Housing Works Bookstore Cafe")
        XCTAssertTrue(housingWorks.waitForExistence(timeout: 5))
        housingWorks.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Workability"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Directions"].exists)
        XCTAssertTrue(app.buttons["Save"].exists)
        XCTAssertTrue(app.buttons["Share"].exists)
        capture("07-detail-evidence")
        // Detail now opens as a sheet from the Spots map (brewdesk#117) —
        // no push, no back button; swipe down to dismiss it.
        app.swipeDown()
        XCTAssertTrue(app.mapPins.firstMatch.waitForExistence(timeout: 5), "Spots did not survive the sheet dismiss")

        // ── 5. Methodology ─────────────────────────────────────────────────
        // The list toolbar's own "How scoring works" entry left with
        // Nearby; the You tab carries it now, independent of the browse
        // surface.
        let youTab = app.tabBars.buttons["tab-you"]
        XCTAssertTrue(youTab.waitForExistence(timeout: 5))
        youTab.waitUntilHittable()
        youTab.tap()
        app.descendants(matching: .any)["methodology-link"].tap()
        XCTAssertTrue(app.navigationBars["How Work Fit works"].waitForExistence(timeout: 3),
                      "Methodology screen did not open from the You tab")
        capture("08-methodology")
        app.tabBars.buttons["tab-spots"].tap()

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

        // ve#46 shipped 2026-08-23: Cupertino is served from the OSM baseline
        // tier, so the reviewer sees real local pins plus the honest banner.
        XCTAssertTrue(app.mapPins.firstMatch.waitForExistence(timeout: 15),
                      "Map emptied for a Cupertino reviewer (brewdesk#1 / bd#108 regression)")
        XCTAssertTrue(app.descendants(matching: .any)["coverage-banner"].waitForExistence(timeout: 5),
                      "Baseline coverage banner missing for a Cupertino reviewer (bd#108)")
        capture("09-map-cupertino-real-viewport")

        // ── 7. Offline mid-browse → relaunch ──────────────────────────────
        // Lands with brewdesk#27's Release-safe fixture seam
        // (`-UITestScenario offline`, ids `map-state-error` / `map-retry`).
        // Until then this step is intentionally absent, not silently passing.

        // ── 8. Relaunch: gates persisted, straight to discovery ───────────
        app.terminate()
        app.launchArguments = englishArguments
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["tab-spots"].waitForExistence(timeout: 8),
                      "Relaunch replayed onboarding instead of restoring discovery")
        XCTAssertFalse(app.buttons["Continue"].exists)
        // Count is viewport-dependent since bd#108 (relaunch restores the
        // last real viewport, e.g. Cupertino's 30, not NYC's 100).
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "work spot")
        ).firstMatch.waitForExistence(timeout: 15),
                      "Relaunch did not restore the venue-count header")
        capture("10-relaunch-restored")
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

        XCTAssertTrue(app.tabBars.buttons["tab-spots"].waitForExistence(timeout: 8))
        let banner = app.descendants(matching: .any)["coverage-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 15),
                      "Baseline coverage banner missing for the baselineCity fixture")
        XCTAssertTrue(app.staticTexts["Baseline data here — not yet researched. NYC is fully researched."].exists)

        // brewdesk#117: Spots (map + shelf) is the only browse surface now;
        // its venue buttons carry the same "<name>, Work Fit <n>, <hood>"
        // shape Nearby's rows used to.
        let pins = app.mapPins
        XCTAssertTrue(pins.firstMatch.waitForExistence(timeout: 15),
                      "baselineCity fixture rendered no venue pins")
        XCTAssertGreaterThanOrEqual(pins.count, 5, "Expected at least 5 baseline venue pins near Cupertino")
        capture("cupertino-baseline-coverage-fixture")
    }

    // MARK: - Helpers

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
        if app.tabBars.buttons["tab-spots"].waitForExistence(timeout: 8) {
            app.tabBars.buttons["tab-spots"].tap()
        }
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
