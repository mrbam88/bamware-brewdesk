import XCTest

/// brewdesk#77 — selecting every filter must never empty the list for the
/// wrong reason. Fixture-driven (`-UITestScenario fixtureOK`): Roasters is
/// cafe/fast/plenty/some-seating/laptop-unrestricted, Reading Room is a
/// library, Corner Cafe is laptop-discouraged.
///
/// brewdesk#118: retargeted from the old Nearby tab's `Menu`
/// (submenu-then-option taps) to the Spots tab's anchored
/// `WorkFitFilterMenu` (segmented option taps, no submenu step — the
/// popover stays open across picks since filters apply live). Taps only;
/// not iterated to green — a stabilization pass covers full pass/fail.
final class FilterUITests: XCTestCase {
    private let wait: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchSpots() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipGates", "-UITestScenario", "fixtureOK"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["tab-spots"].waitForExistence(timeout: wait))
        app.tabBars.buttons["tab-spots"].tap()
        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").waitForExistence(timeout: wait))
        return app
    }

    /// `WorkFitFilterMenu` is a popover that stays open across picks
    /// (filters apply live) — opens it only if it isn't already showing,
    /// unlike the old `Menu` which closed after every selection.
    @MainActor
    private func openFilterMenuIfNeeded(_ app: XCUIApplication) {
        guard !app.descendants(matching: .any)["work-fit-filter-menu"].exists else { return }
        let button = app.buttons["filter-button"]
        XCTAssertTrue(button.waitForExistence(timeout: wait), "filter button missing")
        button.tap()
    }

    /// One segmented option inside a dimension row, e.g. `identifier:
    /// "filter-wifi-fast"` — no submenu step, unlike the old `Menu`'s
    /// labeled-submenu pickers.
    @MainActor
    private func pick(_ app: XCUIApplication, identifier: String) {
        openFilterMenuIfNeeded(app)
        let choice = app.buttons[identifier].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: wait), "\(identifier) option missing")
        choice.tap()
    }

    @MainActor
    private func toggleLaptopFriendly(_ app: XCUIApplication) {
        openFilterMenuIfNeeded(app)
        let toggle = app.switches["filter-laptop-friendly"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: wait))
        toggle.tap()
    }

    @MainActor
    func testSelectingEveryFilterStillShowsQualifyingCafes() throws {
        let app = launchSpots()

        toggleLaptopFriendly(app)
        pick(app, identifier: "filter-wifi-fast")
        pick(app, identifier: "filter-outlets-plenty")
        pick(app, identifier: "filter-seating-some")
        // brewdesk#118: WorkFitFilterMenu has no spot-type dimension (out of
        // scope per the mockups) — the old "Spot type: cafe" pick has no
        // retarget, so Reading Room's library type no longer filters out
        // here; left for the stabilization pass.

        // The qualifying cafe survives "everything selected" (the bug showed
        // zero cafes here); the laptop-hostile cafe drops out.
        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").waitForExistence(timeout: wait),
                      "All filters selected emptied the list (brewdesk#77 regression)")
        XCTAssertFalse(app.mapPin(named: "Fixture Corner Cafe").exists,
                       "Laptop-discouraged cafe should not pass laptop-friendly")
    }

    @MainActor
    func testHonestZeroShowsEmptyStateAndResetRestores() throws {
        let app = launchSpots()

        // Every fixture's seating is KNOWN "some" — a "Plenty" floor is an
        // honest zero, not the bug.
        pick(app, identifier: "filter-seating-plenty")
        XCTAssertTrue(app.descendants(matching: .any)["map-state-empty"]
            .waitForExistence(timeout: wait),
            "Known-below-floor venues must actually filter out")

        openFilterMenuIfNeeded(app)
        let reset = app.descendants(matching: .any)["filters-reset"].firstMatch
        XCTAssertTrue(reset.waitForExistence(timeout: wait))
        reset.tap()
        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").waitForExistence(timeout: wait),
                      "Reset all filters did not restore the list")
    }
}
