import XCTest

/// The "not in BrewDesk yet" card for a tapped Apple base-map café label
/// (bd#182). Apple's own POI labels render in the platform map layer, not
/// the accessibility tree, so XCUITest cannot reliably tap a real one on
/// the simulator — `-brewdesk.apple-feature-fixture` (`LaunchEnvironment`)
/// opens the card directly with a fixed name/coordinate instead, exercising
/// its rendering and actions the same way a real tap would.
final class AppleFeatureCardUITests: XCTestCase {
    private let wait: TimeInterval = 15

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(fixture: String = "Corner Café|40.7128|-74.0060") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", "fixtureOK",
            "-brewdesk.apple-feature-fixture", fixture,
        ]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    func testCardRendersNameDistanceAndBadgeFromFixture() {
        let app = launch()
        XCTAssertTrue(element(app, "apple-feature-card").waitForExistence(timeout: wait))
        XCTAssertTrue(element(app, "apple-feature-name").exists)
        XCTAssertEqual(element(app, "apple-feature-name").label, "Corner Café")
        XCTAssertTrue(element(app, "apple-feature-distance").exists)
        XCTAssertTrue(element(app, "apple-feature-not-in-brewdesk-badge").exists)
        XCTAssertEqual(element(app, "apple-feature-not-in-brewdesk-badge").label, "Not in BrewDesk yet")
    }

    @MainActor
    func testDirectionsAndSuggestActionsExist() {
        let app = launch()
        XCTAssertTrue(element(app, "apple-feature-card").waitForExistence(timeout: wait))
        XCTAssertTrue(app.buttons["apple-feature-directions"].exists)
        XCTAssertTrue(app.buttons["apple-feature-suggest"].exists)
    }

    /// Tapping Suggest calls the stub client (`NullCafeSuggestionClient` in
    /// Debug builds) and flips the button to a disabled "Sent" state —
    /// proves the action wire-up end to end without a real engine endpoint.
    @MainActor
    func testSuggestButtonSendsAndDisables() {
        let app = launch()
        let suggest = app.buttons["apple-feature-suggest"]
        XCTAssertTrue(suggest.waitForExistence(timeout: wait))
        suggest.tap()
        let sentPredicate = NSPredicate(format: "value == %@", "Sent")
        expectation(for: sentPredicate, evaluatedWith: suggest)
        waitForExpectations(timeout: wait)
        XCTAssertFalse(suggest.isEnabled)
    }

    @MainActor
    func testDifferentFixtureNameRenders() {
        let app = launch(fixture: "Ninth Street Espresso|40.7295|-73.9856")
        XCTAssertTrue(element(app, "apple-feature-card").waitForExistence(timeout: wait))
        XCTAssertEqual(element(app, "apple-feature-name").label, "Ninth Street Espresso")
    }
}
