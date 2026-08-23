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

    /// The map tab (Explore) — its search card uses a plain `TextField`,
    /// found by placeholder like `ReviewerSimulationTests` does.
    @MainActor
    private func launchExplore() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipGates", "-UITestScenario", "fixtureOK"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout: wait))
        app.tabBars.buttons["Explore"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["map-header-card"].waitForExistence(timeout: wait))
        return app
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

    /// brewdesk#87 — the map search field had no way to resign focus. A map
    /// tap must dismiss the keyboard without losing what was typed, and the
    /// keyboard's Done button must do the same after refocusing.
    @MainActor
    func testSearchKeyboardDismissesOnMapTapAndDone() throws {
        let app = launchExplore()

        let field = app.textFields["Search cafes"]
        XCTAssertTrue(field.waitForExistence(timeout: wait), "Map search field missing")
        field.tap()
        field.typeText("Gre")
        XCTAssertEqual(app.keyboards.count, 1, "keyboard did not appear after typing")

        // A point inside the map, clear of the header card (top) and the
        // shelf card (bottom half at its default medium detent).
        app.windows.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .tap()
        XCTAssertEqual(app.keyboards.count, 0, "tapping the map did not dismiss the keyboard")
        XCTAssertEqual(field.value as? String, "Gre", "map-tap dismiss must keep the typed text")

        field.tap()
        XCTAssertEqual(app.keyboards.count, 1, "keyboard did not return on refocus")
        let doneButton = app.descendants(matching: .any)["search-done"].firstMatch
        XCTAssertTrue(doneButton.waitForExistence(timeout: wait), "keyboard Done button missing")
        doneButton.tap()
        XCTAssertEqual(app.keyboards.count, 0, "Done button did not dismiss the keyboard")
        XCTAssertEqual(field.value as? String, "Gre", "Done dismiss must keep the typed text")
    }
}
