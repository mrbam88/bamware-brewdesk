import XCTest

/// 1.1 store-listing shots (PR #237, supervisor revision): everything
/// except onboarding (`AppStoreScreenshotTests`). All map/search/filter/
/// saved captures here launch with `-brewdesk.uitest-fixed-location`
/// (bd#198) — a GRANTED, in-process CoreLocation fix — instead of the
/// decline-location path, because the decline path's "Location is off —
/// showing NYC" banner is a degraded state and must never appear in a
/// marketing shot. Filters/search/saved run against PRODUCTION data (no
/// `-UITestScenario`), never the `Fixture *`-named scenario fixtures —
/// a fake venue name in a store screenshot is not acceptable, in any shot.
/// Only the sign-in screen (no venue name on it at all) still uses the
/// deterministic `fixtureOK` scenario. Locale comes from `SCREENSHOT_LOCALE`
/// (`en` default, `es`), same contract as `AppStoreScreenshotTests`.
final class AppStoreScreenshots11Tests: XCTestCase {
    private let wait: TimeInterval = 15
    /// West Village — inside NYC's fully-researched coverage, and the same
    /// fix the supervisor specified.
    private let fixedLat = 40.7335
    private let fixedLng = -74.0027
    /// A real, currently-live production café near the fixed location
    /// (confirmed present on the NoHo/West Village map in PR #237's first
    /// pass) — used everywhere a shot needs a real, nameable venue instead
    /// of a `Fixture *` scenario name.
    private let realVenueQuery = "Think Coffee"
    private let realVenuePrefix = "Think Coffee"

    private struct CaptureLocale {
        let appleLanguage: String
        let appleLocale: String
        let searchField: String
        let saveButton: String

        static let en = CaptureLocale(appleLanguage: "(en)", appleLocale: "en_US", searchField: "Search spots", saveButton: "Save")
        static let es = CaptureLocale(appleLanguage: "(es)", appleLocale: "es_ES", searchField: "Buscar lugares", saveButton: "Guardar")

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

    /// Production launch, granted + fixed location, no degraded-state
    /// banner possible. `-UITestSkipGates` skips onboarding straight to the
    /// Spots map; `-brewdesk.uitest-fixed-location` (bd#198) authorizes
    /// location AND delivers the fixture coordinate in-process — no
    /// `simctl`-side privacy grant needed for the fixture to work, but the
    /// harness also grants it at the OS level before launch (belt and
    /// suspenders, matches the supervisor's explicit instruction) so
    /// nothing about this launch depends on a stale prior grant either way.
    @MainActor
    private func launchGrantedLocation(_ locale: CaptureLocale) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestNoPhotos",
            // A clean saved state every launch — otherwise a save from an
            // earlier run of `testCaptureSavedSpot` on the same simulator
            // persists in UserDefaults and the detail screen's action
            // button reads "Saved" instead of "Save" on the next run.
            "-brewdesk.saved-venue-ids", "()",
            "-brewdesk.uitest-fixed-location", "\(fixedLat)|\(fixedLng)",
            "-AppleLanguages", locale.appleLanguage,
            "-AppleLocale", locale.appleLocale,
        ]
        app.launch()
        XCTAssertTrue(app.spotsTab.waitForExistence(timeout: wait))
        return app
    }

    /// Drags the shelf grabber to `.full` so the sectioned/full list
    /// (rather than the compact rail) renders — mirrors `FilterUITests`'
    /// own local copy of this gesture.
    @MainActor
    private func openFullShelf(_ app: XCUIApplication) {
        let handle = element(app, "map-shelf-grabber").firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: wait), "shelf grabber missing")
        let shelf = element(app, "map-discovery-shelf").firstMatch
        let window = app.windows.firstMatch
        shelf.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: shelf.frame.width / 2, dy: 12))
            .press(
                forDuration: 0.05,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10)),
                withVelocity: .default,
                thenHoldForDuration: 0.2
            )
    }

    // MARK: - 03 (city map) + 01 (evidence / claim provenance)

    @MainActor
    func testCaptureMapAndEvidence() throws {
        let locale = CaptureLocale.current()
        let app = launchGrantedLocation(locale)

        XCTAssertTrue(app.mapPins.firstMatch.waitForExistence(timeout: wait))
        capture("03-work-fit-map", from: app)

        let search = app.textFields[locale.searchField]
        XCTAssertTrue(search.waitForExistence(timeout: wait))
        search.tap()
        search.typeText("Housing Works Bookstore Cafe\n")

        let heading = app.staticTexts["venue-detail-heading"]
        if !heading.waitForExistence(timeout: 12) {
            let housingWorks = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Housing Works")
            ).firstMatch
            XCTAssertTrue(housingWorks.waitForExistence(timeout: 5))
            housingWorks.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: 5))
        // Ticket rule: no Google Places photos prominent in marketing shots.
        XCTAssertFalse(app.buttons.matching(identifier: "photo-thumb").firstMatch.exists)
        capture("01-claim-provenance", from: app)
    }

    // MARK: - 02 (honest filters: confirmed / might-match-unknown), real data

    @MainActor
    func testCaptureHonestFilters() throws {
        let locale = CaptureLocale.current()
        let app = launchGrantedLocation(locale)
        XCTAssertTrue(app.mapPins.firstMatch.waitForExistence(timeout: wait))

        let filterButton = element(app, "filter-button").firstMatch
        XCTAssertTrue(filterButton.waitForExistence(timeout: wait))
        filterButton.tap()
        // "OK" Wi-Fi (not "Fast") against real production data: the strict
        // "Fast" tier came back with zero confirmed matches in this
        // viewport (empty confirmed section, nothing to show) — "OK" is
        // the lenient-enough bar that still produces real confirmed
        // matches. "OK" wifi alone against real data turned out to leave
        // the unknown bucket EMPTY (most real cafés that report Wi-Fi at
        // all clear "OK"), so a second, independent dimension (outlets
        // "Some") is layered on: a venue now needs BOTH attributes
        // resolved to count as confirmed, which is a high enough combined
        // bar that real venues missing just one of the two land in
        // "unknown" instead of "confirmed".
        let okWifi = app.buttons["filter-wifi-ok"].firstMatch
        XCTAssertTrue(okWifi.waitForExistence(timeout: wait))
        okWifi.tap()
        let someOutlets = app.buttons["filter-outlets-some"].firstMatch
        XCTAssertTrue(someOutlets.waitForExistence(timeout: wait))
        someOutlets.tap()
        // A third dimension shrinks the confirmed list to a handful of
        // cards (was 10 for wifi+outlets alone) so this shot's single
        // scroll can show a real confirmed card AND real "might match"
        // rows together, instead of scrolling clean past 10 confirmed
        // cards before the unknown section even enters the frame.
        let someSeating = app.buttons["filter-seating-some"].firstMatch
        XCTAssertTrue(someSeating.waitForExistence(timeout: wait))
        someSeating.tap()
        // Dismiss the popover by tapping the map outside it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()

        let countLine = element(app, "map-count-line").firstMatch
        XCTAssertTrue(countLine.waitForExistence(timeout: wait))

        openFullShelf(app)

        let confirmedSection = element(app, "filter-confirmed-section")
        XCTAssertTrue(confirmedSection.waitForExistence(timeout: wait), "confirmed section missing")
        // The unknown toggle is a no-op while confirmed is empty
        // (DiscoveryShelfCard guards it), so a real confirmed match is
        // required for this shot to show anything at all.
        XCTAssertTrue(
            confirmedSection.buttons.firstMatch.waitForExistence(timeout: wait),
            "confirmed section is empty against real data — the filter is too strict for this viewport"
        )

        // The map header already shows "N match · M unknown" with a real M
        // — but the toggle itself is a LazyVStack row below every confirmed
        // card, so it isn't realized in the accessibility tree until
        // scrolled into view. A full-page `swipeUp()` overshoots past the
        // boundary (the toggle is lazily realized slightly before it's
        // fully on-screen); a short partial drag gives fine enough control
        // to land on a frame that still shows a real confirmed card AND the
        // toggle together.
        let shelf = element(app, "map-discovery-shelf").firstMatch
        func smallScrollUp() {
            shelf.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: shelf.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        }
        let unknownToggle = element(app, "filter-unknown-toggle")
        var toggleFound = unknownToggle.waitForExistence(timeout: 3)
        var scrollAttempts = 0
        while !toggleFound, scrollAttempts < 20 {
            smallScrollUp()
            toggleFound = unknownToggle.waitForExistence(timeout: 1)
            scrollAttempts += 1
        }
        XCTAssertTrue(toggleFound, "unknown toggle missing even after scrolling past the confirmed cards")
        unknownToggle.tap()
        let unknownSection = element(app, "filter-unknown-section")
        XCTAssertTrue(unknownSection.waitForExistence(timeout: wait))
        // One more small scroll brings a couple of expanded "might match"
        // rows into frame below the toggle, while a confirmed card should
        // still be visible near the top (the toggle was only just found).
        smallScrollUp()

        capture("02-honest-filters", from: app)
    }

    // MARK: - 05 (search results) + 06 (recent searches)

    @MainActor
    func testCaptureSearchAndRecents() throws {
        let locale = CaptureLocale.current()
        let app = launchGrantedLocation(locale)
        XCTAssertTrue(app.mapPins.firstMatch.waitForExistence(timeout: wait))

        let search = app.textFields[locale.searchField]
        XCTAssertTrue(search.waitForExistence(timeout: wait))
        search.tap()
        search.typeText("Think")

        let resultRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", realVenuePrefix)
        ).firstMatch
        XCTAssertTrue(resultRow.waitForExistence(timeout: wait), "no real result for a partial 'Think' query")
        capture("05-search-results", from: app)

        resultRow.tap()
        // Selecting a search result opens the detail sheet and commits the
        // field to the venue's own name (bd#219).
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: wait))
        app.dismissDetailSheet()

        let committedLabel = element(app, "search-committed-label")
        XCTAssertTrue(committedLabel.waitForExistence(timeout: wait))
        committedLabel.tap()

        let recents = element(app, "search-recents")
        XCTAssertTrue(recents.waitForExistence(timeout: wait), "recent searches section missing after a real selection")
        capture("06-recent-searches", from: app)
    }

    // MARK: - 07 (Not rated yet), real unrated production venue

    /// The granted-location viewport near the fixed West Village coordinate
    /// turned out to be entirely rated (that core is well-researched) —
    /// `VenueOrdering.observedFirst` also sorts rated venues before unrated
    /// ones in any list, so a citywide search plus scrolling is what
    /// actually reaches a real unrated venue, rather than the plain
    /// viewport list. "coffee" is broad enough to pull in NYC venues well
    /// outside the core, where most of the dataset's ~90% unrated venues
    /// (50-ish rated of 500 total, per the map header) actually live.
    @MainActor
    func testCaptureNotRatedYet() throws {
        let locale = CaptureLocale.current()
        let app = launchGrantedLocation(locale)
        XCTAssertTrue(app.mapPins.firstMatch.waitForExistence(timeout: wait))

        let search = app.textFields[locale.searchField]
        XCTAssertTrue(search.waitForExistence(timeout: wait))
        search.tap()
        search.typeText("coffee")

        let shelf = element(app, "map-discovery-shelf").firstMatch
        XCTAssertTrue(shelf.waitForExistence(timeout: wait))

        let unratedRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", ", not rated yet,")
        ).firstMatch
        var found = unratedRow.waitForExistence(timeout: wait)
        var attempts = 0
        while !found, attempts < 20 {
            shelf.swipeUp()
            found = unratedRow.waitForExistence(timeout: 2)
            attempts += 1
        }
        XCTAssertTrue(found, "no unrated real venue found scrolling a citywide 'coffee' search")
        unratedRow.tap()

        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: wait))
        XCTAssertTrue(element(app, "unobserved-explanation").waitForExistence(timeout: wait))
        capture("07-not-rated-yet", from: app)
    }

    // MARK: - 08: sign-in, Apple/Google at equal prominence

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
        capture("08-sign-in", from: app)
    }

    // MARK: - 09: Saved, with a REAL production venue (not a Fixture name)

    @MainActor
    func testCaptureSavedSpot() throws {
        let locale = CaptureLocale.current()
        let app = launchGrantedLocation(locale)
        XCTAssertTrue(app.mapPins.firstMatch.waitForExistence(timeout: wait))

        let search = app.textFields[locale.searchField]
        XCTAssertTrue(search.waitForExistence(timeout: wait))
        search.tap()
        search.typeText("\(realVenueQuery)\n")

        let heading = app.staticTexts["venue-detail-heading"]
        if !heading.waitForExistence(timeout: 12) {
            let row = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", realVenuePrefix)
            ).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: wait))

        let save = app.buttons[locale.saveButton].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: wait), "Save button missing on a real venue's detail screen")
        save.tap()

        app.dismissDetailSheet()
        XCTAssertTrue(app.savedTab.waitForExistence(timeout: wait))
        app.savedTab.tap()

        let savedRow = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", realVenuePrefix)
        ).firstMatch
        XCTAssertTrue(savedRow.waitForExistence(timeout: wait), "real venue missing from Saved after tapping Save")
        capture("09-saved-spot", from: app)
    }
}
