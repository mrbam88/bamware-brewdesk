import XCTest

/// brewdesk#77 — selecting every filter must never empty the list for the
/// wrong reason. Fixture-driven (`-UITestScenario fixtureOK`): Roasters is
/// cafe/fast/plenty/some-seating/laptop-unrestricted, Reading Room is a
/// library, Corner Cafe is laptop-discouraged.
final class FilterUITests: XCTestCase {
    private let wait: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchNearby() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipGates", "-UITestScenario", "fixtureOK"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Nearby"].waitForExistence(timeout: wait))
        app.tabBars.buttons["Nearby"].tap()
        XCTAssertTrue(app.staticTexts["Fixture Roasters"].waitForExistence(timeout: wait))
        return app
    }

    /// Menus close after each selection; every pick re-opens the menu.
    @MainActor
    private func pick(_ app: XCUIApplication, submenu: String, option: String) {
        app.buttons["Filters"].tap()
        let row = app.buttons[submenu].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: wait), "\(submenu) submenu missing")
        row.tap()
        let choice = app.buttons[option].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: wait), "\(option) option missing")
        choice.tap()
    }

    @MainActor
    private func toggleLaptopFriendly(_ app: XCUIApplication) {
        app.buttons["Filters"].tap()
        let toggle = app.descendants(matching: .any)["Laptop-friendly only"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: wait))
        toggle.tap()
    }

    @MainActor
    func testSelectingEveryFilterStillShowsQualifyingCafes() throws {
        // UI3: filter surface moves to WorkFitFilterMenu — un-skip in #118
        throw XCTSkip("Filters left the Nearby list with brewdesk#117 (UI3 tab restructure); they land on the Spots surface via WorkFitFilterMenu in #118.")
    }

    @MainActor
    func testHonestZeroShowsEmptyStateAndResetRestores() throws {
        // UI3: filter surface moves to WorkFitFilterMenu — un-skip in #118
        throw XCTSkip("Filters left the Nearby list with brewdesk#117 (UI3 tab restructure); they land on the Spots surface via WorkFitFilterMenu in #118.")
    }
}
