import XCTest

/// brewdesk#78 — search-as-you-type. Fixture-driven (`-UITestScenario
/// fixtureOK`): Fixture Roasters (Union Square), Fixture Reading Room
/// (Greenwich Village), Fixture Corner Cafe (Flatiron).
final class SearchUITests: XCTestCase {
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

    @MainActor
    private func searchField(_ app: XCUIApplication) -> XCUIElement {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: wait), "Nearby search field missing")
        return field
    }

    @MainActor
    func testResultsUpdateWhileTypingWithoutSubmit() throws {
        let app = launchNearby()

        let field = searchField(app)
        field.tap()
        field.typeText("Roast")
        // No Search key, no submit — the debounce alone must narrow the list.
        XCTAssertTrue(app.staticTexts["Fixture Reading Room"]
            .waitForNonExistence(timeout: wait),
            "Typing alone did not narrow the list (brewdesk#78)")
        XCTAssertTrue(app.staticTexts["Fixture Roasters"].exists)
        XCTAssertFalse(app.staticTexts["Fixture Corner Cafe"].exists)

        // Case/diacritic-insensitive contains also applies while typing.
        field.typeText("ers")   // "Roasters"
        XCTAssertTrue(app.staticTexts["Fixture Roasters"].waitForExistence(timeout: wait))
    }

    @MainActor
    func testNeighborhoodMatchesWhileTyping() throws {
        let app = launchNearby()

        let field = searchField(app)
        field.tap()
        field.typeText("Greenwich")
        XCTAssertTrue(app.staticTexts["Fixture Reading Room"].waitForExistence(timeout: wait))
        XCTAssertTrue(app.staticTexts["Fixture Roasters"]
            .waitForNonExistence(timeout: wait),
            "Neighborhood match did not narrow the list while typing")
    }

    @MainActor
    func testNoMatchesShowsEmptyStateAndClearingRestores() throws {
        let app = launchNearby()

        let field = searchField(app)
        field.tap()
        field.typeText("zzz nowhere")
        XCTAssertTrue(app.descendants(matching: .any)["list-state-empty"]
            .waitForExistence(timeout: wait),
            "No-match search did not show the empty state")

        // Deleting the query must restore the full list immediately — the
        // model applies an emptied search without waiting for the debounce.
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "zzz nowhere".count))
        XCTAssertTrue(app.staticTexts["Fixture Roasters"].waitForExistence(timeout: wait),
                      "Clearing the search did not restore the list")
        XCTAssertTrue(app.staticTexts["Fixture Reading Room"].exists)
    }
}
