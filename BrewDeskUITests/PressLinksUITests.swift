import XCTest

/// Venue detail "In the press" card (bd#180): allowlisted press links from
/// the engine's `news[]` (ve#103) — title (or source domain when no title),
/// source domain, and a tappable row per link. Fully collapses when the
/// venue carries no `news`, same policy as `businessInfo` (bd#50).
/// Fixture-driven via `-UITestScenario fixtureOK` (see `ScenarioVenueService`):
/// only "Fixture Roasters" carries `news` (one titled link, one title-less
/// link); every other fixture venue has none.
final class PressLinksUITests: XCTestCase {
    private let wait: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launch() -> XCUIApplication {
        // Launch tests rotate the simulator and leave it in landscape; these
        // layout assertions are written for portrait.
        XCUIDevice.shared.orientation = .portrait
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
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // brewdesk#117: detail now opens from the Spots tab's map/shelf (a
    // sheet), not a Nearby-list push — Nearby no longer exists.
    @MainActor
    private func openDetail(_ app: XCUIApplication, venueName: String) {
        XCTAssertTrue(app.spotsTab.waitForExistence(timeout: wait))
        app.spotsTab.tap()
        let pin = app.mapPin(named: venueName)
        XCTAssertTrue(pin.waitForExistence(timeout: wait))
        pin.tap()
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: wait))
    }

    /// The card sits below Workability/Info in a scroll view; sweep it on
    /// screen (and materialize it — the detail body is a LazyVStack).
    @MainActor
    private func revealPressLinks(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Workability"].waitForExistence(timeout: wait))
        app.swipeUp()
        app.swipeUp()
    }

    // MARK: - Present: titled row, title-less row, tap target

    @MainActor
    func testPressLinksShowTitleDomainAndFallBackWhenTitleMissing() {
        let app = launch()
        openDetail(app, venueName: "Fixture Roasters")
        revealPressLinks(app)

        let card = element(app, "press-links")
        XCTAssertTrue(card.waitForExistence(timeout: wait), "In the press card missing")
        capture("press-links-row")

        // Each row collapses into one accessible button (same pattern as
        // `businessRowLabel`'s website/call rows) — assert on the button's
        // combined label rather than nested static text.
        let rows = app.buttons.matching(identifier: "press-link")
        XCTAssertEqual(rows.count, 2, "expected one row per news link")

        let titled = rows.element(boundBy: 0)
        XCTAssertTrue(titled.waitForExistence(timeout: wait))
        XCTAssertTrue(
            titled.label.contains("Fixture Roasters is the best laptop café in the neighborhood"),
            "titled press link's title missing from row label: \(titled.label)"
        )
        XCTAssertTrue(
            titled.label.contains("fixture-press.example"),
            "titled press link's source domain missing from row label: \(titled.label)"
        )

        // Second fixture link has no `title` — the row falls back to the
        // domain as its heading and does not print a duplicate domain line.
        let untitled = rows.element(boundBy: 1)
        XCTAssertTrue(untitled.exists)
        XCTAssertTrue(
            untitled.label.contains("fixture-gazette.example"),
            "title-less press link's domain fallback missing from row label: \(untitled.label)"
        )
    }

    // MARK: - Absent: the card collapses entirely

    /// Fixture Reading Room carries no `news` — the card must not render at
    /// all, matching `businessInfo`'s "no empty shell" policy.
    @MainActor
    func testCardCollapsesWhenVenueHasNoNews() {
        let app = launch()
        openDetail(app, venueName: "Fixture Reading Room")
        revealPressLinks(app)

        XCTAssertFalse(element(app, "press-links").exists, "press-links card rendered with no news")
        XCTAssertEqual(app.buttons.matching(identifier: "press-link").count, 0)
        // The rest of the detail screen is unaffected.
        XCTAssertTrue(app.staticTexts["Workability"].exists)
    }
}
