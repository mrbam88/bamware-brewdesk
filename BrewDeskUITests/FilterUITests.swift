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
        let app = launchNearby()

        toggleLaptopFriendly(app)
        pick(app, submenu: "Wi-Fi", option: "Fast only")
        pick(app, submenu: "Outlets", option: "Plenty")
        pick(app, submenu: "Seating", option: "Some or better")
        pick(app, submenu: "Spot type", option: "cafe")

        // The qualifying cafe survives "everything selected" (the bug showed
        // zero cafes here); the library and the laptop-hostile cafe drop out.
        XCTAssertTrue(app.staticTexts["Fixture Roasters"].waitForExistence(timeout: wait),
                      "All filters selected emptied the list (brewdesk#77 regression)")
        XCTAssertFalse(app.staticTexts["Fixture Reading Room"].exists,
                       "Library should not pass the cafe spot-type filter")
        XCTAssertFalse(app.staticTexts["Fixture Corner Cafe"].exists,
                       "Laptop-discouraged cafe should not pass laptop-friendly")
        XCTAssertFalse(app.descendants(matching: .any)["list-state-empty"].exists)
    }

    @MainActor
    func testHonestZeroShowsEmptyStateAndResetRestores() throws {
        let app = launchNearby()

        // Every fixture's seating is KNOWN "some" — a "Plenty" floor is an
        // honest zero, not the bug.
        pick(app, submenu: "Seating", option: "Plenty")
        XCTAssertTrue(app.descendants(matching: .any)["list-state-empty"]
            .waitForExistence(timeout: wait),
            "Known-below-floor venues must actually filter out")

        app.buttons["Filters"].tap()
        let reset = app.descendants(matching: .any)["filters-reset"].firstMatch
        XCTAssertTrue(reset.waitForExistence(timeout: wait))
        reset.tap()
        XCTAssertTrue(app.staticTexts["Fixture Roasters"].waitForExistence(timeout: wait),
                      "Reset all filters did not restore the list")
    }
}
