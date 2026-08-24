import XCTest

/// Marketing capture: replays the store-listing flow and attaches the five
/// raw screens. Locale comes from the `SCREENSHOT_LOCALE` environment
/// variable (`en` default, `es` supported) — pass it from xcodebuild as
/// `TEST_RUNNER_SCREENSHOT_LOCALE=es`. Launches with `-UITestNoPhotos` so the
/// detail screen collapses its Google Places photo strip and leads with
/// Workability instead (brewdesk#30: no Google photos in marketing shots).
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
        let findMyWorkCafe: String
        let startWhereYouAre: String
        let useUnionSquare: String
        let nearbyTab: String
        let exploreTab: String
        let filters: String
        let laptopFriendlyOnly: String
        let searchField: String
        /// Shape, not literal: the Union Square load is a real API count
        /// from a real-viewport query (bd#108), no longer a fixed number.
        /// bd#37's rank-independence rule applies to counts too — match
        /// the pattern "<digits> work spots", not a specific total.
        let workCafeCountPattern: String
        let oneWorkCafe: String
        let detailsNav: String
        let workability: String

        static let en = CaptureLocale(
            appleLanguage: "(en)",
            appleLocale: "en_US",
            continueButton: "Continue",
            honestHeadline: "Every score shows its work.",
            findMyWorkCafe: "Find my work spot",
            startWhereYouAre: "Start where you are.",
            useUnionSquare: "Use Union Square instead",
            nearbyTab: "Nearby",
            exploreTab: "Explore",
            filters: "Filters",
            laptopFriendlyOnly: "Laptop-friendly only",
            searchField: "Search spots",
            workCafeCountPattern: "^[0-9,]+ work spots$",
            oneWorkCafe: "1 work spot",
            detailsNav: "Details",
            workability: "Workability"
        )

        static let es = CaptureLocale(
            appleLanguage: "(es)",
            appleLocale: "es_ES",
            continueButton: "Continuar",
            honestHeadline: "Cada puntuación muestra su evidencia.",
            findMyWorkCafe: "Encontrar mi lugar de trabajo",
            startWhereYouAre: "Empieza donde estás.",
            useUnionSquare: "Usar Union Square",
            nearbyTab: "Cercanos",
            exploreTab: "Explorar",
            filters: "Filtros",
            laptopFriendlyOnly: "Solo aptos para portátiles",
            searchField: "Buscar lugares",
            workCafeCountPattern: "^[0-9,]+ lugares para trabajar$",
            oneWorkCafe: "1 lugar para trabajar",
            detailsNav: "Detalles",
            workability: "Aptitud para trabajar"
        )

        static func current() -> CaptureLocale {
            switch ProcessInfo.processInfo.environment["SCREENSHOT_LOCALE"] {
            case "es": .es
            default: .en
            }
        }
    }

    @MainActor
    func testCaptureAppStoreScreens() throws {
        let locale = CaptureLocale.current()
        let app = XCUIApplication()
        // A stale granted-location permission (left by an earlier run on the
        // same simulator) leaks a real CoreLocation fix into this launch;
        // bd#108 removed the >50km-from-NYC rejection, so that fix recenters
        // the map on wherever the simulator actually is instead of Union
        // Square, breaking the deterministic NYC dataset this capture
        // depends on. Force a clean not-determined state so "Use Union
        // Square instead" is the only location this run can show.
        app.resetAuthorizationStatus(for: .location)
        app.launchArguments += [
            "-brewdesk.onboarding.complete", "NO",
            "-brewdesk.location-intro.complete", "NO",
            "-UITestNoPhotos",
            // Store-submission builds hide the Account entry, report/block
            // actions, and observation entry card (brewdesk#67). Marketing
            // screenshots must match that shipped surface, not the
            // TestFlight-only superset (brewdesk#68).
            "-UITestStoreSurfaceGated",
            "-AppleLanguages", locale.appleLanguage,
            "-AppleLocale", locale.appleLocale,
        ]
        app.launch()

        XCTAssertTrue(app.buttons[locale.continueButton].waitForExistence(timeout: 8))
        app.buttons[locale.continueButton].tap()
        app.buttons[locale.continueButton].tap()
        XCTAssertTrue(app.staticTexts[locale.honestHeadline].waitForExistence(timeout: 2))
        capture("04-honest-by-design")

        app.buttons[locale.findMyWorkCafe].tap()
        XCTAssertTrue(app.staticTexts[locale.startWhereYouAre].waitForExistence(timeout: 2))
        capture("05-location-is-optional")

        app.buttons[locale.useUnionSquare].tap()
        let workCafeCount = app.staticTexts.element(
            matching: NSPredicate(format: "label MATCHES %@", locale.workCafeCountPattern)
        )
        XCTAssertTrue(workCafeCount.waitForExistence(timeout: 15))
        XCTAssertTrue(app.mapPins.firstMatch.waitForExistence(timeout: 5))
        capture("03-work-fit-map")

        // UI3: filter surface moves to WorkFitFilterMenu — un-skip in #118.
        // brewdesk#117 collapsed Explore + Nearby into one Spots tab; the
        // "02-work-filters" capture (Nearby's list Filters menu) has no
        // home until #118 ports filters onto Spots. Re-shooting a full,
        // filters-included marketing set is also its own follow-up ticket
        // per the #116 epic ("screenshot re-shoot") — this flow keeps
        // proving the rest of the store-submission surface end to end.

        let search = app.textFields[locale.searchField]
        search.tap()
        // "\n" presses the keyboard's return/search key without depending on
        // its localized label.
        search.typeText("Housing Works\n")
        XCTAssertTrue(app.staticTexts[locale.oneWorkCafe].waitForExistence(timeout: 15))

        let housingWorks = app.mapPin(named: "Housing Works Bookstore Cafe")
        XCTAssertTrue(housingWorks.waitForExistence(timeout: 5))
        housingWorks.tap()
        XCTAssertTrue(app.navigationBars[locale.detailsNav].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[locale.workability].waitForExistence(timeout: 2))
        // Ticket rule: no Google Places photos prominent in marketing shots.
        // -UITestNoPhotos nils the photo service, so no thumbnail may exist.
        XCTAssertFalse(app.buttons.matching(identifier: "photo-thumb").firstMatch.exists)
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
