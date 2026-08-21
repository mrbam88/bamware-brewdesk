import XCTest

final class AppStoreScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureAppStoreScreens() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-brewdesk.onboarding.complete", "NO",
            "-brewdesk.location-intro.complete", "NO",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 8))
        app.buttons["Continue"].tap()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Every score shows its work."].waitForExistence(timeout: 2))
        capture("04-honest-by-design")

        app.buttons["Find my work cafe"].tap()
        XCTAssertTrue(app.staticTexts["Start where you are."].waitForExistence(timeout: 2))
        capture("05-location-is-optional")

        app.buttons["Use Union Square instead"].tap()
        XCTAssertTrue(app.staticTexts["100 work cafés"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.mapPins.firstMatch.waitForExistence(timeout: 5))
        capture("03-work-fit-map")

        app.tabBars.buttons["Nearby"].tap()
        XCTAssertTrue(app.navigationBars["Nearby"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.venueRows.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Filters"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Laptop-friendly only"].waitForExistence(timeout: 2))
        capture("02-work-filters")
        app.descendants(matching: .any)["Laptop-friendly only"].tap()

        app.tabBars.buttons["Explore"].tap()

        let search = app.textFields["Search cafes"]
        search.tap()
        search.typeText("Housing Works")
        app.keyboards.buttons["Search"].tap()
        XCTAssertTrue(app.staticTexts["1 work café"].waitForExistence(timeout: 15))

        app.tabBars.buttons["Nearby"].tap()
        XCTAssertTrue(app.staticTexts["Housing Works Bookstore Cafe"].waitForExistence(timeout: 5))
        app.staticTexts["Housing Works Bookstore Cafe"].tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Workability"].waitForExistence(timeout: 2))
        capture("01-claim-provenance")
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
