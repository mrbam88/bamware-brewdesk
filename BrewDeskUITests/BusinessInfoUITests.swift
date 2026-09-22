import XCTest

/// Venue detail business-info card (brewdesk#50, #56): structured hours with a
/// deterministic open-now badge — rendered in the device locale's clock (the
/// en-US simulator must show AM/PM, never military time) — website, call, and
/// email rows, raw-string fallback for unparseable hours, and full collapse
/// when the venue carries none of it.
/// Fixture-driven via `-UITestScenario fixtureOK` (see `ScenarioVenueService`);
/// the badge's clock is pinned with `-brewdesk.uitest-fixed-now` so open/closed
/// assertions cannot drift with the machine or the hour the suite runs.
final class BusinessInfoUITests: XCTestCase {
    private let wait: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launch(fixedNow: String) -> XCUIApplication {
        // Launch tests rotate the simulator and leave it in landscape; these
        // layout assertions are written for portrait.
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", "fixtureOK",
            "-brewdesk.saved-venue-ids", "()",
            "-brewdesk.uitest-fixed-now", fixedNow,
        ]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    // brewdesk#117: detail now opens from the Spots tab's map/shelf (a
    // sheet), not a Nearby-list push — Nearby no longer exists.
    //
    // brewdesk#170: for a venue that isn't first/nearest (here, "Fixture
    // Corner Cafe" and "Fixture Reading Room" — second/third of the three
    // fixtures), plain `mapPin(named:)` had nothing on-screen to return:
    // this scenario's map annotations carry no `map-marker`/
    // `map-selected-marker` AX element at the default camera position
    // (verified from a failing run's UI-hierarchy dump — no such identifier
    // exists anywhere in the tree, not a stale-frame race), so the helper's
    // documented fallback (`matches.firstMatch`) correctly, honestly
    // returns the only real match: the discovery shelf's horizontally-
    // scrolled-off-screen rail card. Tapping that fails with "Activation
    // point invalid", and a raw `shelf.swipeLeft()` proved unreliable in
    // practice (one swipe overshot Reading Room clean off the OTHER edge,
    // x=-357 — the rail appears to snap/decelerate past a single gesture
    // rather than settling predictably). Typing the venue's name into
    // Search is the reliable alternative already proven by `SearchUITests`
    // (debounce-narrows-while-typing, no `Return`/server round trip, so
    // this doesn't touch the citywide-search codepath under repair
    // elsewhere): it narrows to exactly one match, which is always the
    // first/only — and therefore on-screen — card.
    @MainActor
    private func openDetail(_ app: XCUIApplication, venueName: String) {
        XCTAssertTrue(app.spotsTab.waitForExistence(timeout: wait))
        app.spotsTab.tap()
        let search = app.textFields["Search spots"]
        XCTAssertTrue(search.waitForExistence(timeout: wait))
        search.tap()
        search.typeText(venueName)
        let pin = app.mapPin(named: venueName)
        XCTAssertTrue(pin.waitForExistence(timeout: wait), "\(venueName) did not narrow into view")
        pin.tap()
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: wait))
    }

    /// The card sits below Workability in a scroll view; one swipe brings it
    /// on screen (and materializes it — the detail body is a LazyVStack).
    @MainActor
    private func revealBusinessInfo(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Workability"].waitForExistence(timeout: wait))
        app.swipeUp()
    }

    // MARK: - Present: structured hours, open state, links

    /// Wednesday 10:00 against "Mo-Fr 07:00-19:00; Sa-Su 08:00-18:00" → open.
    @MainActor
    func testStructuredHoursShowOpenNowWithWebsiteCallAndEmailRows() {
        let app = launch(fixedNow: "2026-08-19T10:00")
        openDetail(app, venueName: "Fixture Roasters")
        revealBusinessInfo(app)

        XCTAssertTrue(element(app, "business-info-card").waitForExistence(timeout: wait))
        XCTAssertTrue(element(app, "business-hours-structured").exists,
                      "OSM hours did not render as a structured schedule")
        XCTAssertFalse(element(app, "business-hours-raw").exists,
                       "raw fallback shown alongside structured hours")

        let badge = element(app, "hours-open-badge")
        XCTAssertTrue(badge.exists, "open-now badge missing")
        XCTAssertEqual(badge.label, "Open now")

        XCTAssertTrue(app.buttons["business-website"].exists, "website row missing")
        XCTAssertTrue(app.buttons["business-call"].exists, "call row missing")
        XCTAssertFalse(app.buttons["business-email"].exists, "email row removed (bd#80)")
    }

    /// bd#56: the en-US simulator must render parsed hours on a 12-hour
    /// clock ("7:00 AM – 7:00 PM"), never the OSM string's military time.
    @MainActor
    func testStructuredHoursRenderTwelveHourClockOnEnUSDevice() {
        let app = launch(fixedNow: "2026-08-19T10:00")
        openDetail(app, venueName: "Fixture Roasters")
        revealBusinessInfo(app)

        let structured = element(app, "business-hours-structured")
        XCTAssertTrue(structured.waitForExistence(timeout: wait))
        let twelveHour = structured.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "AM", "PM")
        )
        XCTAssertGreaterThan(twelveHour.count, 0,
                             "no schedule row shows an AM/PM time on an en-US device")
        let military = structured.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "07:00")
        )
        XCTAssertEqual(military.count, 0,
                       "military time leaked into the structured schedule")
    }

    /// Same venue, Wednesday 22:00 → past the 19:00 close → closed.
    @MainActor
    func testStructuredHoursShowClosedNowAfterClose() {
        let app = launch(fixedNow: "2026-08-19T22:00")
        openDetail(app, venueName: "Fixture Roasters")
        revealBusinessInfo(app)

        let badge = element(app, "hours-open-badge")
        XCTAssertTrue(badge.waitForExistence(timeout: wait))
        XCTAssertEqual(badge.label, "Closed now")
    }

    // MARK: - Fallback: unparseable hours stay raw, no open/closed claim

    /// "Daily 8am–5pm" is not OSM syntax: the exact string renders and no
    /// open-now badge appears — a wrong claim is worse than no claim.
    @MainActor
    func testUnparseableHoursFallBackToRawStringWithoutBadge() {
        let app = launch(fixedNow: "2026-08-19T10:00")
        openDetail(app, venueName: "Fixture Corner Cafe")
        revealBusinessInfo(app)

        XCTAssertTrue(element(app, "business-info-card").waitForExistence(timeout: wait))
        let raw = element(app, "business-hours-raw")
        XCTAssertTrue(raw.exists, "raw hours fallback missing")
        XCTAssertEqual(raw.label, "Daily 8am–5pm")
        XCTAssertFalse(element(app, "hours-open-badge").exists,
                       "open/closed claimed for unparseable hours")
        XCTAssertFalse(element(app, "business-hours-structured").exists)
        // Corner Cafe has no website/phone/email: hours-only card, no dead rows.
        XCTAssertFalse(app.buttons["business-website"].exists)
        XCTAssertFalse(app.buttons["business-call"].exists)
        XCTAssertFalse(app.buttons["business-email"].exists)
    }

    // MARK: - Absent: the card collapses entirely

    /// Fixture Reading Room has no hours, website, or phone: the card must
    /// not render at all — no empty shell, no layout gap.
    @MainActor
    func testCardCollapsesWhenVenueHasNoBusinessInfo() {
        let app = launch(fixedNow: "2026-08-19T10:00")
        openDetail(app, venueName: "Fixture Reading Room")
        revealBusinessInfo(app)

        XCTAssertFalse(element(app, "business-info-card").exists,
                       "business-info card rendered with nothing to show")
        XCTAssertFalse(element(app, "hours-open-badge").exists)
        XCTAssertFalse(app.buttons["business-website"].exists)
        XCTAssertFalse(app.buttons["business-call"].exists)
        XCTAssertFalse(app.buttons["business-email"].exists)
        // The rest of the detail screen is unaffected.
        XCTAssertTrue(app.staticTexts["Workability"].exists)
    }
}
