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
        // shelf card. bd#219: while the search field has focus (as it is
        // here — this taps BEFORE any dismiss), `DiscoveryShelfCard` is at
        // `fullHeight` (~70% of the map) regardless of its resting detent,
        // not the medium-detent ~50% a fixed normalized offset used to
        // assume — the old 0.35 sat inside that fuller search-mode shelf,
        // so this only ever dismissed the keyboard via the SHELF's own
        // touch gesture (a bug in its own right, since fixed: see the
        // `minimumDistance: 8` change on that gesture) rather than the MAP
        // tap this test is actually about. The real gap between the header
        // and the search-focused shelf is narrow (measured ~70pt on a
        // 874pt-tall window) — computed here from the header's own real
        // frame, with a fixed point margin, rather than a hand-picked
        // normalized fraction that a different device height/Dynamic Type
        // size would silently put back inside one of the two.
        let headerFrame = app.descendants(matching: .any)["map-header-card"].frame
        let windowFrame = app.windows.firstMatch.frame
        let tapY = min(headerFrame.maxY + 55, windowFrame.height * 0.3)
        app.windows.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: tapY / windowFrame.height))
            .tap()
        XCTAssertEqual(app.keyboards.count, 0, "tapping the map did not dismiss the keyboard")
        XCTAssertEqual(field.value as? String, "Gre", "map-tap dismiss must keep the typed text")

        // bd#182/bd#219: the tap point above is chosen to clear this
        // screen's own SwiftUI chrome (header, shelf), but MapKit's base
        // layer can still render a selectable Apple POI label anywhere on
        // it (bd#182's `.mapFeatureSelectionContent`) — landing on one
        // opens `AppleFeatureCard` a moment later as an unrelated side
        // effect of proving this test's actual point (a plain map tap
        // resigns focus). Polls rather than a single check-then-swipe: the
        // sheet's own presentation can still be mounting the instant after
        // the tap. Dismisses defensively so the assertions below aren't
        // blocked by an incidental sheet this test isn't about.
        let appleFeatureCard = app.otherElements["apple-feature-card"]
        let dismissDeadline = Date().addingTimeInterval(2)
        while Date() < dismissDeadline {
            if appleFeatureCard.exists {
                // Swiping on the CARD element itself (not the whole app) —
                // the card only covers the bottom ~260-280pt of the screen,
                // so a generic `app.swipeDown()` starting from the window's
                // center misses its drag handle entirely.
                appleFeatureCard.swipeDown()
                _ = appleFeatureCard.waitForNonExistence(timeout: 2)
            }
            if field.isHittable { break }
            Thread.sleep(forTimeInterval: 0.1)
        }

        XCTAssertTrue(field.waitUntilHittable(timeout: wait), "search field never became hittable again after the dismiss")
        field.tap()
        XCTAssertTrue(
            Self.waitFor(timeout: wait) { app.keyboards.count == 1 },
            "keyboard did not return on refocus"
        )
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
    /// bd#223 (requirement 5 — "no camera moves while typing") revises this:
    /// the ORIGINAL version of this test typed the query and asserted the
    /// camera moved with NO Search/return, because that auto-fit-while-
    /// typing was exactly the bug in Bilal's report (a one-letter query
    /// fit the camera across the whole metro area while he was still
    /// typing). Updated to press Search/return before asserting the fit —
    /// the camera-moves-to-results behavior this test was written to prove
    /// still holds, just gated on an explicit submit instead of every
    /// keystroke. `testTypingNeverMovesTheCameraButSearchDoes` below is the
    /// new, direct coverage for the "never while typing" half.
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
        // bd#223: types, THEN presses Search — typing alone must not move
        // the camera any more (see `testTypingNeverMovesTheCameraButSearchDoes`).
        field.typeText("Roasters\n")

        XCTAssertTrue(poll(timeout: wait) { matchCount() == 2 },
                      "pressing Search did not bring the map pin back onto the panned-away viewport " +
                      "(got \(matchCount()) matches, want 2 — shelf card + map pin)")
        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").waitUntilHittable(timeout: wait),
                      "search-centered result pin is not hittable")
    }

    /// bd#223 (requirement 5) — the direct reproduction of Bilal's report:
    /// typing alone, with NO Search/return, must never move the camera —
    /// not even onto a result it unambiguously, uniquely matches. Must FAIL
    /// on `origin/main` (brewdesk#158's auto-fit ran on every keystroke) and
    /// PASS on this branch.
    @MainActor
    func testTypingNeverMovesTheCameraButSearchDoes() throws {
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
        func metersBetween(_ a: (lat: Double, lng: Double), _ b: (lat: Double, lng: Double)) -> Double {
            let earthRadiusM = 6_371_000.0
            let dLat = (b.lat - a.lat) * .pi / 180
            let dLng = (b.lng - a.lng) * .pi / 180
            let x = sin(dLat / 2) * sin(dLat / 2)
                + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
            return earthRadiusM * 2 * atan2(sqrt(x), sqrt(1 - x))
        }
        func parseCoordinate(_ raw: String?) -> (lat: Double, lng: Double)? {
            guard let raw else { return nil }
            let parts = raw.components(separatedBy: ",")
            guard parts.count == 2, let lat = Double(parts[0]), let lng = Double(parts[1]) else { return nil }
            return (lat, lng)
        }

        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").waitForExistence(timeout: wait))

        let window = app.windows.firstMatch
        let panStart = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        let panEnd = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
        for _ in 0..<10 {
            panStart.press(forDuration: 0.05, thenDragTo: panEnd)
        }
        XCTAssertTrue(poll(timeout: wait) { matchCount() == 1 }, "panning away did not cull the map pin")

        let cameraCenter = app.descendants(matching: .any)["map-camera-center"]
        XCTAssertTrue(cameraCenter.waitForExistence(timeout: wait))

        // Focus the field FIRST and let the keyboard-driven relayout settle
        // before taking the "before" snapshot — focusing alone (independent
        // of this ticket) nudges MapKit's `.onMapCameraChange` resync once
        // as the visible frame's aspect ratio changes under the keyboard,
        // which would otherwise be misattributed to typing.
        let field = searchField(app)
        field.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: wait), "keyboard never appeared")
        var lastCenter = cameraCenter.value as? String
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.15)
            let now = cameraCenter.value as? String
            if now == lastCenter { break }
            lastCenter = now
        }
        let centerBeforeTyping = parseCoordinate(lastCenter)
        XCTAssertNotNil(centerBeforeTyping, "could not parse the camera center before typing")

        // A single, UNAMBIGUOUS local match — the strongest possible case
        // for the old auto-fit to have fired. No Search key pressed.
        field.typeText("Roasters")
        // Generous settle window — the OLD behavior's debounce was 260ms;
        // this waits well past it before asserting nothing moved.
        Thread.sleep(forTimeInterval: 1.2)

        // bd#223's own contract is "no CAMERA MOVE while typing" — not
        // "the reported centre never drifts by a single metre". Even on
        // this branch, `model.venues` narrowing while typing still re-syncs
        // `visibleRegion` from the live camera image via `MapProxy.convert`
        // (brewdesk#157, pre-existing and untouched by this ticket) — a
        // harmless few-hundred-metre reporting artifact from the keyboard's
        // predictive-text bar nudging the map's measured height, not an
        // actual pan. `cameraMoveToleranceMeters` is sized comfortably
        // above that noise floor and comfortably below what the OLD bug
        // produced (see the assertion below): panning the pin fully out of
        // view, then having the camera fly back onto a single unambiguous
        // result, moves it by many KILOMETRES (this fixture is ~26km from
        // where the pan leaves the camera) — `matchCount()` (whether the
        // real MapKit annotation re-enters the culled viewport) is this
        // test's primary, unambiguous signal; the distance check is a
        // secondary, generous sanity bound on the same claim.
        let cameraMoveToleranceMeters = 2_500.0
        if let before = centerBeforeTyping, let after = parseCoordinate(cameraCenter.value as? String) {
            let moved = metersBetween(before, after)
            XCTAssertLessThanOrEqual(
                moved, cameraMoveToleranceMeters,
                "typing alone moved the map camera \(Int(moved))m — bd#223 requirement 5 regression " +
                "(this is the exact bug: a query matched while typing fitting the camera to it)"
            )
        }
        XCTAssertEqual(
            matchCount(), 1,
            "typing alone brought the culled pin back on screen (got \(matchCount()), want 1 — shelf only)"
        )

        // Pressing Search/return DOES move it — same result this file's
        // other search-fit tests already prove, checked here too so this
        // test can't pass by accident (e.g. a camera that never moves at all).
        field.typeText("\n")
        XCTAssertTrue(poll(timeout: wait) { matchCount() == 2 }, "pressing Search never moved the camera onto the result")
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
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: wait), "keyboard never appeared after tapping the field")
        // bd#223: presses Search — a citywide result landing while the user
        // is still typing must not fit the camera on its own any more (see
        // `testTypingNeverMovesTheCameraButSearchDoes`); pressing Search
        // both records the recent and arms the fit once the server answers,
        // which resolves to exactly one word-prefix match here and so
        // becomes a full PR #220 selection (`selectSearchResult`) — a
        // strictly stronger proof than the original bounding-box fit this
        // test used to rely on.
        field.typeText("Ferry Roasters\n")

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

    /// bd#223 (B2 — "I can't scroll the listing!! When typing!?"). Must FAIL
    /// on `origin/main` (the competing shelf-drag-resigns-focus gesture
    /// swallowed the scroll before the `ScrollView` ever recognized it) and
    /// PASS on this branch. Uses `manyVenues` (2,180 fixtures) so the
    /// focused, empty-query "browse" list genuinely needs scrolling —
    /// `fixtureOK`'s 3 rows might already fully fit above the keyboard.
    @MainActor
    func testResultsListScrollsWithTheKeyboardUp() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipGates", "-UITestScenario", "manyVenues"]
        app.launch()
        XCTAssertTrue(app.spotsTab.waitForExistence(timeout: wait))
        app.spotsTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map-header-card"].waitForExistence(timeout: wait))

        let field = searchField(app)
        field.tap()
        XCTAssertEqual(app.keyboards.count, 1, "keyboard did not appear")

        let shelf = app.descendants(matching: .any)["map-discovery-shelf"]
        XCTAssertTrue(shelf.waitForExistence(timeout: wait), "discovery shelf missing")

        let firstRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Perf Cafe")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: wait), "browse-all list showed no rows while focused")
        let beforeY = firstRow.frame.minY
        // bd#223 B2 root cause: the OLD competing shelf-drag gesture
        // resigned focus and collapsed the card from full height back to
        // `.medium`'s horizontal rail — which ALSO happens to move a
        // "Perf Cafe…"-labelled row's `frame.minY` (the rail renders the
        // same venues, just horizontally, at the collapsed card's shallower
        // height), so a bare "did minY change" check can't tell a genuine
        // scroll apart from that collapse. The shelf's own HEIGHT is the
        // unambiguous signal: a collapse shrinks it dramatically; a scroll
        // leaves it exactly where it was.
        let shelfHeightBefore = shelf.frame.height
        // A second, independent signal: the horizontal rail caps at
        // `model.venues.prefix(12)` — collect every "Perf Cafe…" row
        // currently in the accessibility tree so a genuine scroll (which
        // brings rows the rail could NEVER show) is distinguishable from a
        // collapse (which can only ever re-show a subset of this same set).
        let rowsBeforeScroll = Set(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Perf Cafe")).allElementsBoundByIndex.map(\.label)
        )

        for _ in 0..<6 {
            shelf.swipeUp()
        }

        XCTAssertTrue(
            Self.waitFor(timeout: wait) { firstRow.frame.minY != beforeY || !firstRow.exists },
            "swiping the results list under the keyboard did not scroll it (bd#223 B2) — " +
            "first row stayed pinned at y=\(beforeY)"
        )
        XCTAssertTrue(shelf.exists, "shelf disappeared while scrolling the results list")
        XCTAssertGreaterThan(
            shelf.frame.height, shelfHeightBefore * 0.9,
            "shelf collapsed from full height to the horizontal rail while scrolling (bd#223 B2) — " +
            "was \(shelfHeightBefore)pt, now \(shelf.frame.height)pt"
        )
        XCTAssertTrue(
            Self.waitFor(timeout: wait) {
                let now = Set(
                    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Perf Cafe")).allElementsBoundByIndex.map(\.label)
                )
                return !now.isSubset(of: rowsBeforeScroll)
            },
            "scrolling never brought any row into view that wasn't already visible before — " +
            "the list only ever showed the same handful of rows (bd#223 B2)"
        )
    }

    /// bd#223 (requirement 4). The button must not just be invisible — it
    /// must not exist at all — while the search field has focus.
    @MainActor
    func testLocateButtonDoesNotExistWhileSearchFieldIsFocused() throws {
        let app = launchSpots()
        let locate = app.buttons["map-locate-me"]
        XCTAssertTrue(locate.waitForExistence(timeout: wait), "locate button missing before search")

        let field = searchField(app)
        field.tap()
        XCTAssertTrue(
            Self.waitFor(timeout: wait) { !locate.exists },
            "locate button still exists while the search field is focused"
        )

        let cancel = app.descendants(matching: .any)["search-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: wait))
        cancel.tap()
        XCTAssertTrue(locate.waitForExistence(timeout: wait), "locate button never returned after Cancel")
    }

    /// bd#219 — "selecting a far-away café must fly the map to it
    /// (Google-Maps-like)". Root cause: the shelf's row-tap callback only
    /// ever set a plain, un-biased `.region(...)` with no walking-scale
    /// fly-to, AND a late citywide server answer's own `scheduleSearchFit`
    /// re-fit (bd#200/#158) could land AFTER the tap and override the
    /// selection's camera position entirely. Reuses bd#200's
    /// `cityWideSearch` fixture and `Fixture Ferry Roasters` (St. George,
    /// ~13.5km from the default Union Square viewport — see
    /// `testCityWideSearchFindsACafeOutsideTheViewport` above), extended
    /// (bd#219 2nd revision) with five more St. George fixture cafés
    /// (`ScenarioVenueService.farawaySurroundingVenues`) so the selection's
    /// OWN surroundings reload has real neighbours to find. This must FAIL
    /// on `origin/main` (no fly-to/selection guard/zoom lock exists there)
    /// and PASS on the fix branch.
    ///
    /// Asserts OBJECTIVE, numeric proof of the camera's real zoom and the
    /// selected marker's real screen position — not a distance tolerance
    /// around a computed target, which passed even when the actual
    /// rendered camera was several kilometres wide (bd#219 2nd revision:
    /// the supervisor's own review of the first fix's contact sheet found
    /// exactly this — a correct-looking `visibleRegion`-derived test
    /// passing while the REAL MapKit camera, driven by a separate stale
    /// write, was nowhere close).
    @MainActor
    func testSelectingAFarAwaySearchResultFliesTheMapToIt() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipGates", "-UITestScenario", "cityWideSearch"]
        app.launch()
        XCTAssertTrue(app.spotsTab.waitForExistence(timeout: wait))
        app.spotsTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map-header-card"].waitForExistence(timeout: wait))

        let field = searchField(app)
        field.tap()
        field.typeText("Ferry Roasters")

        // Scoped to the SHELF specifically (not `mapPin(named:)`, which
        // deliberately matches either the shelf row or the real MapKit
        // annotation — see its own doc comment): the ticket's flow is "type
        // the name, tap the row", and tapping the real annotation instead
        // would bypass `selectSearchResult` entirely (a plain pin tap just
        // sets `selected` with no fly-to/guard behavior).
        let shelf = app.descendants(matching: .any)["map-discovery-shelf"]
        XCTAssertTrue(shelf.waitForExistence(timeout: wait), "discovery shelf missing")
        let row = shelf.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture Ferry Roasters,")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: wait), "search result row for the far café never appeared")

        // The header count line BEFORE the tap — while search is active it
        // reflects only the name matches (here, just the one far café), not
        // the neighbourhood. Captured now so the post-selection assertion
        // below has something concrete to differ from.
        let countLine = app.descendants(matching: .any)["map-count-line"].firstMatch
        XCTAssertTrue(countLine.waitForExistence(timeout: wait), "map count line missing")
        let matchCountText = countLine.label

        // bd#219: `waitUntilHittable` (not a bare `.tap()` the instant the
        // row exists) — the row can appear an instant before the search
        // list's own crossfade/layout settles, and a tap landing mid-settle
        // risks missing the row's real hit-test area even though the
        // accessibility tree already reports it as "existing".
        XCTAssertTrue(row.waitUntilHittable(timeout: wait), "search result row never became hittable")
        // `isHittable` can flip true a beat before the search list's own
        // settle/crossfade animation actually finishes, AND before
        // `scheduleSearchFit`'s own in-flight "fit all results" pass (still
        // running from typing — this row only exists once its citywide
        // server answer landed, which is the SAME event that can retrigger
        // that fit) has applied and gotten out of the way. A tap that lands
        // before both settle risks a `Button` tap gesture racing a list
        // reflow (brewdesk#158's own comment on this exact hazard) and
        // being lost. A fixed settle wait is cheap insurance against both.
        Thread.sleep(forTimeInterval: 1.5)
        row.tap()

        // The selected teardrop — 30pt head, café name in its label — must
        // exist and be hittable in the now-visible map area above the
        // `.medium` sheet, whether or not the far café made it into this
        // fetch's own (fixture-limited) loaded set: `map-selected-marker`
        // is the dedicated identifier for the "always render the selection,
        // never let it be culled/skipped" fallback (bd#212, extended here).
        let selectedMarker = app.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "map-selected-marker", "Fixture Ferry Roasters,")
        ).firstMatch
        XCTAssertTrue(selectedMarker.waitForExistence(timeout: wait), "selected teardrop for the far café never appeared")
        XCTAssertTrue(selectedMarker.waitUntilHittable(timeout: wait), "selected teardrop is not hittable")

        // The detail sheet's heading shows the far café's own name.
        let heading = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Fixture Ferry Roasters")).firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: wait), "detail sheet never opened on the far café")

        // The search field COMMITS: it now shows the café's name as static
        // text (not an editable query), with the clear (x) affordance.
        let committedLabel = app.descendants(matching: .any)["search-committed-label"]
        XCTAssertTrue(committedLabel.waitForExistence(timeout: wait), "search field never committed to the selected café's name")
        XCTAssertEqual(committedLabel.label, "Selected café: Fixture Ferry Roasters")
        XCTAssertTrue(app.buttons["search-clear-selection"].exists, "clear (x) affordance missing after commit")

        // Committing the search stops filtering `venues` by the typed
        // text and loads the neighbourhood around the café instead — the
        // header count line must settle to something other than the
        // search's own match count.
        XCTAssertTrue(
            Self.waitFor(timeout: wait) {
                let current = countLine.label
                return current != matchCountText
            },
            "header count line still reads the search match count (\(matchCountText)) after committing the selection"
        )

        // bd#219 (supervisor 2nd revision): OBJECTIVE proof of the REAL
        // rendered camera — a `visibleRegion`-derived distance-to-target
        // check (the first revision's approach) can pass even while the
        // actual MapKit camera is kilometres wide, because a stale write
        // from elsewhere can win the render without ever touching
        // `visibleRegion` again. `map-camera-mpp`/`map-rendered-marker-
        // count` are test-flag-gated accessibility values reporting the
        // real settled zoom and how many markers the planner is drawing;
        // the selected marker's own on-screen frame (read directly, not
        // reconstructed from a region) proves where it visually landed.
        let mppElement = app.descendants(matching: .any)["map-camera-mpp"]
        let markerCountElement = app.descendants(matching: .any)["map-rendered-marker-count"]
        let headerElement = app.descendants(matching: .any)["map-header-card"]
        let detailScreenElement = app.descendants(matching: .any)["venue-detail-screen"]

        func currentMetersPerPoint() -> Double? { Double((mppElement.value as? String) ?? "") }
        func currentMarkerCount() -> Int? { Int((markerCountElement.value as? String) ?? "") }
        /// The selected marker's screen-space vertical fraction within the
        /// band from the search header's bottom edge to the detail sheet's
        /// top edge — the "visible area above the medium sheet" the ticket
        /// specifies, read from REAL frames, not a computed estimate.
        func markerBandFraction() -> Double? {
            guard headerElement.exists, detailScreenElement.exists, selectedMarker.exists else { return nil }
            let bandTop = headerElement.frame.maxY
            let bandBottom = detailScreenElement.frame.minY
            guard bandBottom > bandTop else { return nil }
            return (selectedMarker.frame.midY - bandTop) / (bandBottom - bandTop)
        }

        XCTAssertTrue(
            Self.waitFor(timeout: wait) { (currentMetersPerPoint() ?? .greatestFiniteMagnitude) <= 2.6 },
            "camera never settled to walking scale — mpp=\(currentMetersPerPoint().map { "\($0)" } ?? "nil"), want ≤2.6"
        )
        // Note: `mpp` alone can already read ≤2.6 from the FIRST-pass
        // estimate, before `correctFlyTargetForSettledSheet`'s corrective
        // write (a separate, slightly later async step) lands — so this
        // must poll for the band fraction to settle, not take a single
        // immediate reading right after the mpp check above.
        var firstBandFraction: Double?
        XCTAssertTrue(
            Self.waitFor(timeout: wait) {
                firstBandFraction = markerBandFraction()
                guard let firstBandFraction else { return false }
                return firstBandFraction >= 0.35 && firstBandFraction <= 0.65
            },
            "selected marker never settled within the visible band — last reading: " +
            "\(firstBandFraction.map { "\($0)" } ?? "nil"), want within 0.35–0.65 " +
            "(header bottom=\(headerElement.frame.maxY), sheet top=\(detailScreenElement.frame.minY), " +
            "marker frame=\(selectedMarker.frame))"
        )
        // The surroundings fetch (`loadSurroundings` → `model.updateViewport`
        // → the app's own `.task(id: request)` load) is a separate async
        // hop from the camera settling — poll rather than a single read.
        XCTAssertTrue(
            Self.waitFor(timeout: wait) { (currentMarkerCount() ?? 0) >= 5 },
            "fewer than 5 markers rendered after the surroundings load (count=\(currentMarkerCount().map { "\($0)" } ?? "nil"))"
        )

        // All three still true 4s later — no late fit (a delayed citywide
        // answer re-running `scheduleSearchFit`, or this selection's own
        // surroundings reload changing `model.venues` again) pulls the
        // camera back out.
        Thread.sleep(forTimeInterval: 4)
        XCTAssertLessThanOrEqual(
            currentMetersPerPoint() ?? .greatestFiniteMagnitude, 2.6,
            "camera zoomed back out 4s after settling — mpp=\(currentMetersPerPoint().map { "\($0)" } ?? "nil")"
        )
        if let laterBandFraction = markerBandFraction() {
            XCTAssertTrue(
                laterBandFraction >= 0.35 && laterBandFraction <= 0.65,
                "selected marker drifted to \(laterBandFraction) of the visible band 4s later, want within 0.35–0.65"
            )
        } else {
            XCTFail("could not compute the selected marker's band position 4s later")
        }
        XCTAssertGreaterThanOrEqual(
            currentMarkerCount() ?? 0, 5,
            "marker count dropped below 5 4s later (count=\(currentMarkerCount().map { "\($0)" } ?? "nil"))"
        )

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "search-select-flies-to-far-cafe"
        attachment.lifetime = .keepAlways
        add(attachment)

        // ...and after dismissing the sheet: the camera and its
        // surroundings must stay exactly where they landed (no band check
        // here — the sheet, and so the band it defined, is gone).
        let closeButton = app.buttons["detail-close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: wait), "detail close button missing")
        closeButton.tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertLessThanOrEqual(
            currentMetersPerPoint() ?? .greatestFiniteMagnitude, 2.6,
            "camera zoom changed after dismissing the sheet — mpp=\(currentMetersPerPoint().map { "\($0)" } ?? "nil")"
        )
        XCTAssertGreaterThanOrEqual(
            currentMarkerCount() ?? 0, 5,
            "marker count dropped below 5 after dismissing the sheet (count=\(currentMarkerCount().map { "\($0)" } ?? "nil"))"
        )
        // `selected` becomes nil on dismiss, so the café's marker is no
        // longer THE "selected" one (a plain `map-marker`, not
        // `map-selected-marker` — bd#212's fallback only special-cases the
        // ACTIVELY selected venue) — it must still be ON the map, though,
        // now as a normal marker among the loaded surroundings.
        let cafeMarkerAfterDismiss = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Fixture Ferry Roasters,")
        ).firstMatch
        XCTAssertTrue(cafeMarkerAfterDismiss.waitForExistence(timeout: wait), "café marker disappeared after dismissing the sheet")
    }

    // MARK: - Helpers

    /// Polls `condition` until it's true or `timeout` elapses — for state
    /// (like the keyboard's own appear animation) that settles a beat after
    /// the triggering tap rather than synchronously with it.
    private static func waitFor(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return condition()
    }
}
