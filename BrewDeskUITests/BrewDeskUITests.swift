import XCTest

final class BrewDeskUITests: XCTestCase {
    @MainActor
    func testDiscoveryTabsExist() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-UITestSkipGates")
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Nearby"].exists)
        XCTAssertTrue(app.tabBars.buttons["About"].exists)

        app.tabBars.buttons["About"].tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["BrewDesk"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["OpenStreetMap contributors"].exists)
    }
}
