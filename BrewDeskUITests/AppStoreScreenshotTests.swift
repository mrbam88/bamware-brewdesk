import XCTest

/// Marketing capture: onboarding only. Locale comes from the
/// `SCREENSHOT_LOCALE` environment variable (`en` default, `es`
/// supported) — pass it from xcodebuild as `TEST_RUNNER_SCREENSHOT_LOCALE=es`.
///
/// 1.1 supervisor review (PR #237): the map/filters/detail/search/saved
/// shots moved to `AppStoreScreenshots11Tests`, which launches with a
/// granted, fixed CoreLocation fix (`-brewdesk.uitest-fixed-location`)
/// instead of declining location — the decline path's "Location is off —
/// showing NYC" banner is a degraded state and must never appear in a
/// marketing shot. This class keeps only the one shot that's genuinely
/// about the onboarding flow itself (04): the location-is-optional page
/// (formerly 05) was dropped so a real "location is optional" claim isn't
/// made twice — the sign-in screen and the granted-location map together
/// already carry that message honestly.
final class AppStoreScreenshotTests: XCTestCase {
    /// Every user-visible string the flow touches, per capture locale. The
    /// values mirror `BrewDesk/Localizable.xcstrings`; if a translation
    /// changes there, the capture fails loudly here instead of shipping a
    /// stale screenshot.
    private struct CaptureLocale {
        let appleLanguage: String
        let appleLocale: String
        let continueButton: String
        let honestHeadline: String

        static let en = CaptureLocale(
            appleLanguage: "(en)",
            appleLocale: "en_US",
            continueButton: "Continue",
            honestHeadline: "Every score shows its work."
        )

        static let es = CaptureLocale(
            appleLanguage: "(es)",
            appleLocale: "es_ES",
            continueButton: "Continuar",
            honestHeadline: "Cada puntuación muestra su evidencia."
        )

        static func current() -> CaptureLocale {
            switch ProcessInfo.processInfo.environment["SCREENSHOT_LOCALE"] {
            case "es": .es
            default: .en
            }
        }
    }

    @MainActor
    func testCaptureOnboarding() throws {
        let locale = CaptureLocale.current()
        let app = XCUIApplication()
        app.launchArguments += [
            "-brewdesk.onboarding.complete", "NO",
            "-brewdesk.location-intro.complete", "NO",
            "-UITestNoPhotos",
            "-AppleLanguages", locale.appleLanguage,
            "-AppleLocale", locale.appleLocale,
        ]
        app.launch()

        XCTAssertTrue(app.buttons[locale.continueButton].waitForExistence(timeout: 8))
        app.buttons[locale.continueButton].tap()
        app.buttons[locale.continueButton].tap()
        XCTAssertTrue(app.staticTexts[locale.honestHeadline].waitForExistence(timeout: 2))
        capture("04-honest-by-design")
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
