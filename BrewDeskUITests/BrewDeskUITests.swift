import XCTest

final class BrewDeskUITests: XCTestCase {
    @MainActor
    func testDiscoveryTabsExist() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-UITestSkipGates")
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Nearby"].exists)
        XCTAssertTrue(app.tabBars.buttons["Saved"].exists)

        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 2))
        app.buttons["About"].tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["BrewDesk"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["OpenStreetMap contributors"].exists)
    }

    @MainActor
    func testSpanishDiscoveryNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-AppleLanguages", "(es)",
            "-AppleLocale", "es_US",
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Explorar"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Cercanos"].exists)
        XCTAssertTrue(app.tabBars.buttons["Guardados"].exists)
    }

    @MainActor
    func testOnboardingAtAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-brewdesk.onboarding.complete", "NO",
            "-brewdesk.location-intro.complete", "NO",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Your next desk might serve espresso."].exists)
    }

    @MainActor
    func testOnboardingAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-brewdesk.onboarding.complete", "NO",
            "-brewdesk.location-intro.complete", "NO",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 8))

        try app.performAccessibilityAudit()
    }

    @MainActor
    func testSaveCafeFromDetails() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-brewdesk.saved-venue-ids", "",
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Nearby"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Nearby"].tap()
        let cafe = app.staticTexts["Gregorys Coffee"].firstMatch
        XCTAssertTrue(cafe.waitForExistence(timeout: 15))
        cafe.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 3))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Saved"].waitForExistence(timeout: 2))

        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Gregorys Coffee"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testVenueDetailAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-UITestSkipGates")
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Nearby"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Nearby"].tap()
        let cafe = app.staticTexts["Housing Works Bookstore Cafe"].firstMatch
        XCTAssertTrue(cafe.waitForExistence(timeout: 15))
        cafe.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 3))

        try app.performAccessibilityAudit(for: [
            .contrast,
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .textClipped,
            .trait,
        ])
    }

    @MainActor
    func testVenueDetailAtAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Nearby"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Nearby"].tap()
        let cafe = app.staticTexts["Housing Works Bookstore Cafe"].firstMatch
        XCTAssertTrue(cafe.waitForExistence(timeout: 15))
        cafe.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Workability"].exists)
        XCTAssertTrue(app.buttons["Directions"].exists)
        XCTAssertTrue(app.buttons["Save"].exists)
        XCTAssertTrue(app.buttons["Share"].exists)
    }
}
