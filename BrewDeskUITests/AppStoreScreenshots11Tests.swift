import XCTest

/// 1.1 store-listing additions: two shots the original `AppStoreScreenshotTests`
/// flow doesn't reach — the sign-in screen (Apple/Google at equal prominence,
/// bd#174/AccountFlowUITests) and a populated Saved spots list. Both run
/// against the deterministic `fixtureOK` scenario rather than production, so
/// they stay stable regardless of what the live dataset looks like on any
/// given day (unlike `03-work-fit-map`, which intentionally shoots production
/// for real pin density). Locale comes from `SCREENSHOT_LOCALE` (`en`
/// default, `es`), same contract as `AppStoreScreenshotTests`.
final class AppStoreScreenshots11Tests: XCTestCase {
    private struct CaptureLocale {
        let appleLanguage: String
        let appleLocale: String

        static let en = CaptureLocale(appleLanguage: "(en)", appleLocale: "en_US")
        static let es = CaptureLocale(appleLanguage: "(es)", appleLocale: "es_ES")

        static func current() -> CaptureLocale {
            switch ProcessInfo.processInfo.environment["SCREENSHOT_LOCALE"] {
            case "es": .es
            default: .en
            }
        }
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func capture(_ name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 06: the You tab's "Your account" entry opens the shared package's
    /// SignInScreen, showing Apple and Google at equal prominence — the same
    /// screen `AccountFlowUITests.testSignInScreenOffersAppleAtEqualProminenceToGoogleAndEmail`
    /// pins for Guideline 4.8. Never taps either button: both present a real
    /// system sheet XCUITest cannot drive deterministically.
    @MainActor
    func testCaptureSignInScreen() throws {
        let locale = CaptureLocale.current()
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", "fixtureOK",
            "-brewdesk.saved-venue-ids", "()",
            "-AppleLanguages", locale.appleLanguage,
            "-AppleLocale", locale.appleLocale,
        ]
        app.launch()

        XCTAssertTrue(app.youTab.waitForExistence(timeout: 10))
        app.youTab.tap()
        let entry = element(app, "account-entry")
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()

        let apple = element(app, "account-sign-in-apple")
        let google = element(app, "account-sign-in-google")
        XCTAssertTrue(apple.waitForExistence(timeout: 10))
        XCTAssertTrue(google.waitForExistence(timeout: 10), "Google button missing although GIDClientID is configured")
        capture("06-sign-in", from: app)
    }

    /// 07: Saved tab with one hydrated spot (Fixture Roasters, seeded via
    /// `-brewdesk.saved-venue-ids`) instead of the empty state — proves the
    /// feature exists without depending on production data or a live save.
    @MainActor
    func testCaptureSavedSpot() throws {
        let locale = CaptureLocale.current()
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", "fixtureOK",
            "-brewdesk.saved-venue-ids", "(\"fixture-roasters\")",
            "-AppleLanguages", locale.appleLanguage,
            "-AppleLocale", locale.appleLocale,
        ]
        app.launch()

        XCTAssertTrue(app.savedTab.waitForExistence(timeout: 10))
        app.savedTab.tap()
        let row = app.staticTexts["Fixture Roasters"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        capture("07-saved-spot", from: app)
    }
}
