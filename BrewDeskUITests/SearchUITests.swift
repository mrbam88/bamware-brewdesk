import XCTest

/// brewdesk#78 — search-as-you-type. Fixture-driven (`-UITestScenario
/// fixtureOK`): Fixture Roasters (Union Square), Fixture Reading Room
/// (Greenwich Village), Fixture Corner Cafe (Flatiron).
///
/// brewdesk#117: Nearby's `.searchable` list field is gone with the tab.
/// `VenuesModel.searchQuery` debounce-filters `venues` regardless of which
/// screen's field is bound to it, so every case here still holds against
/// the Spots tab's own `TextField` (`CafeMapScreen.searchHeader`) — ported,
/// not skipped. `WorkFitFilterMenu`-specific coverage stays in FilterUITests
/// (skipped until #118; that's a different surface, not this debounce).
final class SearchUITests: XCTestCase {
    private let wait: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchSpots() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipGates", "-UITestScenario", "fixtureOK"]
        app.launch()
        XCTAssertTrue(app.spotsTab.waitForExistence(timeout: wait))
        app.spotsTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map-header-card"].waitForExistence(timeout: wait))
        return app
    }

    @MainActor
    private func searchField(_ app: XCUIApplication) -> XCUIElement {
        let field = app.textFields["Search spots"]
        XCTAssertTrue(field.waitForExistence(timeout: wait), "Spots search field missing")
        return field
    }

    @MainActor
    func testResultsUpdateWhileTypingWithoutSubmit() throws {
        let app = launchSpots()

        let field = searchField(app)
        field.tap()
        field.typeText("Roast")
        // No Search key, no submit — the debounce alone must narrow the list.
        XCTAssertTrue(app.mapPin(named: "Fixture Reading Room").waitForNonExistence(timeout: wait),
                      "Typing alone did not narrow the list (brewdesk#78)")
        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").exists)
        XCTAssertFalse(app.mapPin(named: "Fixture Corner Cafe").exists)

        // Case/diacritic-insensitive contains also applies while typing.
        field.typeText("ers")   // "Roasters"
        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").waitForExistence(timeout: wait))
    }

    @MainActor
    func testNeighborhoodMatchesWhileTyping() throws {
        let app = launchSpots()

        let field = searchField(app)
        field.tap()
        field.typeText("Greenwich")
        XCTAssertTrue(app.mapPin(named: "Fixture Reading Room").waitForExistence(timeout: wait))
        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").waitForNonExistence(timeout: wait),
                      "Neighborhood match did not narrow the list while typing")
    }

    @MainActor
    func testNoMatchesShowsEmptyStateAndClearingRestores() throws {
        let app = launchSpots()

        let field = searchField(app)
        field.tap()
        field.typeText("zzz nowhere")
        XCTAssertTrue(app.descendants(matching: .any)["map-state-empty"]
            .waitForExistence(timeout: wait),
            "No-match search did not show the empty state")

        // Deleting the query must restore the full list immediately — the
        // model applies an emptied search without waiting for the debounce.
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "zzz nowhere".count))
        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").waitForExistence(timeout: wait),
                      "Clearing the search did not restore the list")
        XCTAssertTrue(app.mapPin(named: "Fixture Reading Room").exists)
    }

    /// brewdesk#157 — clearing a search must never leave the map pinless
    /// while the shelf collapses too. A stale `visibleRegion` used to make
    /// the viewport-culled annotation plan return zero pins after the
    /// clear (nothing re-planned off a search-driven data change), and the
    /// shelf's own empty-body bug meant it stayed blank rather than showing
    /// its loading/empty state — only a relaunch brought pins back.
    @MainActor
    func testClearingSearchRestoresMapPinsAndShelfCards() throws {
        let app = launchSpots()

        let field = searchField(app)
        field.tap()
        field.typeText("Roast")
        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").waitForExistence(timeout: wait))
        XCTAssertTrue(app.mapPin(named: "Fixture Reading Room").waitForNonExistence(timeout: wait),
                      "search did not narrow the list before the clear")

        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Roast".count))

        // The bug: the map went pinless and the shelf collapsed after the
        // clear, and only a relaunch brought them back.
        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").waitForExistence(timeout: wait),
                      "clearing the search left the map pinless (brewdesk#157)")
        XCTAssertTrue(app.mapPin(named: "Fixture Reading Room").waitForExistence(timeout: wait))
        XCTAssertTrue(app.mapPin(named: "Fixture Corner Cafe").waitForExistence(timeout: wait))
        XCTAssertTrue(app.descendants(matching: .any)["map-discovery-shelf"].exists,
                      "discovery shelf missing after the search clear")
        XCTAssertFalse(app.descendants(matching: .any)["map-state-empty"].exists,
                       "shelf still showed its empty state after the clear restored venues")
    }

    /// brewdesk#87 — the map search field had no way to resign focus. A map
    /// tap must dismiss the keyboard without losing what was typed, and the
    /// keyboard's Done button must do the same after refocusing.
    @MainActor
    func testSearchKeyboardDismissesOnMapTapAndDone() throws {
        let app = launchSpots()

        let field = app.textFields["Search spots"]
        XCTAssertTrue(field.waitForExistence(timeout: wait), "Map search field missing")
        field.tap()
        field.typeText("Gre")
        XCTAssertEqual(app.keyboards.count, 1, "keyboard did not appear after typing")

        // A point inside the map, clear of the header card (top) and the
        // shelf card (bottom half at its default medium detent).
        app.windows.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .tap()
        XCTAssertEqual(app.keyboards.count, 0, "tapping the map did not dismiss the keyboard")
        XCTAssertEqual(field.value as? String, "Gre", "map-tap dismiss must keep the typed text")

        field.tap()
        XCTAssertEqual(app.keyboards.count, 1, "keyboard did not return on refocus")
        // brewdesk#158: the app ships a "Cancel" trailing control while the
        // search field has focus (`search-cancel`, `CafeMapScreen.swift`'s
        // `searchHeader`) — there is no separate keyboard "Done" button, and
        // this identifier was stale (never shipped as `search-done`).
        let cancelButton = app.descendants(matching: .any)["search-cancel"].firstMatch
        XCTAssertTrue(cancelButton.waitForExistence(timeout: wait), "search Cancel control missing")
        cancelButton.tap()
        XCTAssertEqual(app.keyboards.count, 0, "Cancel did not dismiss the keyboard")
        XCTAssertEqual(field.value as? String, "Gre", "Cancel dismiss must keep the typed text")
    }

    /// brewdesk#158 — search moves the camera to its results (critique
    /// finding 9: a one-result search left the map showing an unrelated
    /// neighborhood with no pin in view).
    ///
    /// `mapPin(named:)` alone can't prove this: "Fixture Roasters" matches
    /// its predicate twice at once — the shelf's horizontal rail card
    /// (`DiscoveryShelfCard`, always on screen and never filtered by
    /// viewport — see its `model.venues.prefix(12)` rail) *and* the real
    /// MapKit annotation, and `mapPin(named:)` deliberately treats either as
    /// "on screen" (its doc comment in `UITestHelpers.swift`). So instead
    /// this counts raw matches: 2 means both the shelf card and the map pin
    /// exist, 1 means only the shelf card does (the map pin was culled off
    /// the current viewport — see `MapAnnotationPlanner`). Every fixture
    /// venue already sits inside the default launch camera (see the other
    /// tests above, which never pan first), so this pans away first to
    /// drive the count to 1, then searches and asserts it returns to 2 —
    /// only possible if the search itself moved the camera back onto the
    /// result.
    @MainActor
    func testSearchMovesCameraToOffScreenResult() throws {
        let app = launchSpots()

        func matchCount() -> Int {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture Roasters,")).count
        }
        func poll(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            repeat {
                if condition() { return true }
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            } while Date() < deadline
            return condition()
        }

        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").waitForExistence(timeout: wait))

        // Pan far away, staying clear of the header (top) and shelf card
        // (bottom half at the default medium detent — same clear zone
        // `testSearchKeyboardDismissesOnMapTapAndDone` taps), and let the
        // settle-driven re-plan (brewdesk#157) cull the pin.
        let window = app.windows.firstMatch
        let panStart = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        let panEnd = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
        for _ in 0..<10 {
            panStart.press(forDuration: 0.05, thenDragTo: panEnd)
        }
        XCTAssertTrue(poll(timeout: wait) { matchCount() == 1 },
                      "panning away did not cull the map pin (got \(matchCount()) matches, want 1 — shelf card only)")

        let field = searchField(app)
        field.tap()
        field.typeText("Roasters")

        XCTAssertTrue(poll(timeout: wait) { matchCount() == 2 },
                      "search did not bring the map pin back onto the panned-away viewport " +
                      "(got \(matchCount()) matches, want 2 — shelf card + map pin)")
        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").waitUntilHittable(timeout: wait),
                      "search-centered result pin is not hittable")
    }

    /// bd#200 — "Search must be city-wide". Root cause: `VenuesModel.venues`
    /// used to be a purely LOCAL filter over whatever pins the current
    /// viewport had already loaded, so a café outside that viewport —
    /// however exact the typed name — could never appear, exactly the bug
    /// Bilal hit typing "Conwell". `cityWideSearch` serves the normal three
    /// Union Square fixtures for a plain viewport load, plus a fourth café
    /// (`Fixture Ferry Roasters`, St. George, ~13.5km away — outside every
    /// viewport radius this app ever queries with) ONLY when `q` matches it —
    /// the same shape as the real engine's `q` contract. This must FAIL on
    /// `origin/main` (no server search exists there to find it at all) and
    /// PASS once bd#200's citywide search ships.
    @MainActor
    func testCityWideSearchFindsACafeOutsideTheViewport() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipGates", "-UITestScenario", "cityWideSearch"]
        app.launch()
        XCTAssertTrue(app.spotsTab.waitForExistence(timeout: wait))
        app.spotsTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map-header-card"].waitForExistence(timeout: wait))

        func matchCount() -> Int {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture Ferry Roasters,")).count
        }
        func poll(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            repeat {
                if condition() { return true }
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            } while Date() < deadline
            return condition()
        }

        // The far café is nowhere at all before searching — the default
        // Union Square viewport never loaded it (proves this is a genuine
        // citywide find, not something already on screen).
        XCTAssertEqual(matchCount(), 0, "far café was already on screen before any search")

        let field = searchField(app)
        field.tap()
        field.typeText("Ferry Roasters")

        // 2 == both the shelf row (bd#200's server result landed in
        // `venues`) AND the real map pin (the camera moved onto it,
        // `scheduleSearchFit`/bd#158) — same rank-independent proof
        // `testSearchMovesCameraToOffScreenResult` above uses.
        XCTAssertTrue(poll(timeout: wait) { matchCount() == 2 },
                      "citywide search never surfaced the far café's row and pin " +
                      "(got \(matchCount()) matches, want 2)")
        XCTAssertTrue(app.mapPin(named: "Fixture Ferry Roasters").waitUntilHittable(timeout: wait),
                      "citywide search result pin is not hittable")
    }
}
