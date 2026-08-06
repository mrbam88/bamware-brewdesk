import XCTest

final class BamwareCafeUITests: XCTestCase {
    @MainActor
    func testDiscoveryTabsExist() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-UITestSkipGates")
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Nearby"].exists)
        XCTAssertTrue(app.tabBars.buttons["Ask"].exists)
        XCTAssertTrue(app.tabBars.buttons["Account"].exists)

        app.tabBars.buttons["Ask"].tap()
        XCTAssertTrue(app.textFields["conversation-composer"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["conversation-send"].exists)
    }
}
