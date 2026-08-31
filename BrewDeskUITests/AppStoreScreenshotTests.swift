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
            searchField: "Search spots",
            workCafeCountPattern: "^[0-9,]+ of [0-9,]+ spots$",
            oneWorkCafe: "1 of ",
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
            searchField: "Buscar lugares",
            workCafeCountPattern: "^[0-9.,]+ de [0-9.,]+ lugares$",
            oneWorkCafe: "1 de ",
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
        // UI3: the single count line ("N of M spots") replaced the old
        // "N work spots" text. Identifier + shape, never an exact count
        // (brewdesk#37/#131).
        let workCafeCount = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND label MATCHES %@",
                "map-count-line",
                locale.workCafeCountPattern
            )
        ).firstMatch
        XCTAssertTrue(workCafeCount.waitForExistence(timeout: 15))
        XCTAssertTrue(app.mapPins.firstMatch.waitForExistence(timeout: 5))
        capture("03-work-fit-map")

        // UI3 (#118): the Work Fit filter menu is home again — reinstate
        // the 02 capture with the score-tier legend on screen.
        let filterButton = app.descendants(matching: .any)["filter-button"].firstMatch
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5))
        filterButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["work-fit-filter-menu"].firstMatch
                .waitForExistence(timeout: 5)
        )
        capture("02-work-filters")
        // Dismiss by tapping the map area outside the anchored menu.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).tap()

        // UI3: filter surface moves to WorkFitFilterMenu — un-skip in #118.
        // brewdesk#117 collapsed Explore + Nearby into one Spots tab; the
        // "02-work-filters" capture (Nearby's list Filters menu) has no
        // home until #118 ports filters onto Spots. Re-shooting a full,
        // filters-included marketing set is also its own follow-up ticket
        // per the #116 epic ("screenshot re-shoot") — this flow keeps
        // proving the rest of the store-submission surface end to end.

        let search = app.textFields[locale.searchField]
        search.tap()
        search.typeText("Housing Works\n")
        // UI3 (#118): focused search shows a vertical result list above the
        // keyboard, and the count line narrows to "1 of M". Open the detail
        // from the result row — the map is behind the list now.
        let narrowed = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND label BEGINSWITH %@",
                "map-count-line",
                locale.oneWorkCafe
            )
        ).firstMatch
        XCTAssertTrue(narrowed.waitForExistence(timeout: 15))

        let housingWorks = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Housing Works")
        ).firstMatch
        XCTAssertTrue(housingWorks.waitForExistence(timeout: 5))
        housingWorks.tap()
        // brewdesk#119: the nav title is now the venue's own name (not a
        // localized "Details"/"Detalles" constant), so this keys off the
        // detail root's identifier instead — locale-independent.
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: 5))
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
