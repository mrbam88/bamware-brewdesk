import XCTest

/// brewdesk#149, real CoreLocation (no `-UITestLocation*` seam): with the
/// simulator's location privacy RESET for the bundle (`xcrun simctl privacy
/// <udid> reset location io.bamware.brewdesk`) and the gates skipped, the
/// Spots map must show the undetermined banner and tapping "Use my location"
/// must raise the system permission alert.
final class LocationRealPermissionTests: XCTestCase {
    @MainActor
    func testResetPermissionShowsBannerAndSystemAlert() {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipGates", "-UITestScenario", "fixtureOK", "-brewdesk.saved-venue-ids", "()"]
        app.launch()
        let banner = app.descendants(matching: .any)["location-undetermined-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "banner missing — is location really notDetermined?")
        app.buttons["location-request-access"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "system location alert did not appear")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "system-location-alert"; attachment.lifetime = .keepAlways
        add(attachment)
        let allow = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'While Using'")).firstMatch
        XCTAssertTrue(allow.exists, "alert buttons: \(alert.buttons.allElementsBoundByIndex.map(\.label))")
        allow.tap()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 10), "banner should clear after Allow")
    }
}
