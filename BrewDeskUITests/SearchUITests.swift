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

    /// bd#219 — "selecting a far-away café must fly the map to it
    /// (Google-Maps-like)". Root cause: the shelf's row-tap callback only
    /// ever set a plain, un-biased `.region(...)` with no walking-scale
    /// fly-to, AND a late citywide server answer's own `scheduleSearchFit`
    /// re-fit (bd#200/#158) could land AFTER the tap and override the
    /// selection's camera position entirely. Reuses bd#200's
    /// `cityWideSearch` fixture and `Fixture Ferry Roasters` (St. George,
    /// ~13.5km from the default Union Square viewport — see
    /// `testCityWideSearchFindsACafeOutsideTheViewport` above) rather than
    /// adding a new one. This must FAIL on `origin/main` (no fly-to or
    /// selection guard exists there) and PASS on the fix branch.
    @MainActor
    func testSelectingAFarAwaySearchResultFliesTheMapToIt() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipGates", "-UITestScenario", "cityWideSearch"]
        app.launch()
        XCTAssertTrue(app.spotsTab.waitForExistence(timeout: wait))
        app.spotsTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map-header-card"].waitForExistence(timeout: wait))

        let farCafeLat = 40.6437
        let farCafeLng = -74.0787
        // bd#219 (supervisor revision): the fly-to's visible-area target is
        // NOT the raw café coordinate — `selectSearchResult` biases the
        // camera CENTER north so the café lands centered in the visible
        // portion above the `.medium`-detent detail sheet (roughly half the
        // screen). `CafeMapScreen.searchFitRegion`'s own formula, fed the
        // fixed 1:2 synthetic ratio `selectSearchResult` uses
        // (`mediumSheetSyntheticMapHeight`/`ObscuredHeight`), computes that
        // target deterministically: obscuredFraction 0.5 ⇒ latitudeDelta =
        // walkingZoomSpan/0.5, shift = 0.25×latitudeDelta. Duplicated here
        // (not imported — UI test targets can't import the app's package
        // target) so this test checks the camera against the SAME precise
        // target the app computes, not a loose tolerance around the café
        // itself.
        let walkingZoomSpan = 0.009
        let expectedLatitudeDelta = walkingZoomSpan / 0.5
        let expectedShiftDegrees = 0.25 * expectedLatitudeDelta
        let expectedTargetLat = farCafeLat - expectedShiftDegrees
        let toleranceMeters = 150.0

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

        let center = app.descendants(matching: .any)["map-camera-center"]
        XCTAssertTrue(center.waitForExistence(timeout: wait), "map camera center accessibility element missing")

        // (a) within 3s the camera center is within 150m of the VISIBLE-
        // area-centred target (not the raw café coordinate).
        let flyDeadline = Date().addingTimeInterval(3)
        var closest = Double.greatestFiniteMagnitude
        while Date() < flyDeadline {
            if let coordinate = Self.parseCoordinate(center.value as? String) {
                closest = min(closest, Self.metersBetween(coordinate.lat, coordinate.lng, expectedTargetLat, farCafeLng))
                if closest <= toleranceMeters { break }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertLessThanOrEqual(
            closest, toleranceMeters,
            "tapping the far café's search result never flew the camera within \(toleranceMeters)m of the " +
            "computed visible-area target (closest: \(closest)m) — camera-center value: \(center.value ?? "nil")"
        )

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

        // (b) still there 4s later — no late fit (a delayed citywide answer
        // re-running `scheduleSearchFit`, or this selection's own
        // surroundings reload changing `model.venues` again) pulls it away.
        Thread.sleep(forTimeInterval: 4)
        guard let stillThere = Self.parseCoordinate(center.value as? String) else {
            XCTFail("camera center unreadable after the settle window")
            return
        }
        let driftedMeters = Self.metersBetween(stillThere.lat, stillThere.lng, expectedTargetLat, farCafeLng)
        XCTAssertLessThanOrEqual(
            driftedMeters, toleranceMeters,
            "the camera drifted \(driftedMeters)m off the visible-area target 4s after selecting it — a late fit pulled it away"
        )
        XCTAssertTrue(selectedMarker.exists, "selected teardrop disappeared after the settle window")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "search-select-flies-to-far-cafe"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Helpers

    /// `"lat,lng"` (see `CafeMapScreen.cameraCenterAccessibilityValue`).
    /// Duplicated from `MapLocateButtonUITests` — UI test targets can't
    /// import the app's package target to share it.
    private static func parseCoordinate(_ raw: String?) -> (lat: Double, lng: Double)? {
        guard let raw else { return nil }
        let parts = raw.components(separatedBy: ",")
        guard parts.count == 2, let lat = Double(parts[0]), let lng = Double(parts[1]) else { return nil }
        return (lat, lng)
    }

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

    private static func metersBetween(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let earthRadiusM = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusM * c
    }
}
