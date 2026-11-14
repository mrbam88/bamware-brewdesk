import XCTest

/// bd#267: cafés load on their own when the map comes to rest somewhere new
/// — a pan past the threshold dispatches a NEW viewport query with no tap.
/// The "Search this area" pill (bd#192) is only the manual fallback now:
/// it shows when the map is zoomed out too far for an automatic fetch (or
/// one failed), and tapping it still refetches the viewport on screen.
///
/// `fixtureOK` (and every other `ScenarioVenueService` scenario) returns the
/// same venues regardless of the query's lat/lng/radius, so this suite
/// proves the re-query through `map-last-query` — an accessibility value
/// exposing what `VenuesModel` actually last dispatched — rather than
/// through the venue list changing (see `CafeMapScreen.swift`'s doc comment
/// on that element).
final class MapSearchAreaUITests: XCTestCase {
    private let wait: TimeInterval = 15

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launchFixtures(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += extraArguments + [
            "-UITestSkipGates",
            "-UITestScenario", "fixtureOK",
            // A real CoreLocation fix landing mid-test (e.g. a simulator
            // with location previously granted from local dev work) would
            // fight this suite's own viewport updates via
            // `DiscoveryRootView`'s `updateCenterIfNeeded` short-circuit —
            // pin `.notDetermined` so every center/radius change this file
            // observes came from the pan/pill under test, not GPS.
            "-UITestLocationUndetermined",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func lastQuery(_ app: XCUIApplication) -> (lat: Double, lng: Double, radiusM: Int)? {
        guard let raw = element(app, "map-last-query").value as? String else { return nil }
        let parts = raw.components(separatedBy: ",")
        guard parts.count == 3,
              let lat = Double(parts[0]), let lng = Double(parts[1]), let radius = Int(parts[2])
        else { return nil }
        return (lat, lng, radius)
    }

    /// Several fast, same-direction drags so the camera's settled center
    /// ends up well past auto-load's 35%-of-visible-span threshold — a
    /// single short drag is too small to guarantee that on every simulator/
    /// zoom combination (same reasoning `MapPerformanceUITests.scriptedPan`
    /// documents for its own repeated drags).
    @MainActor
    private func panFarWest(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        for _ in 0..<4 {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45))
                .press(
                    forDuration: 0.03,
                    thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.45)),
                    withVelocity: .fast,
                    thenHoldForDuration: 0.05
                )
        }
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A city-wide opening camera (m/pt), past auto-load's 40 m/pt limit —
    /// the one state where the pill is the only way to refetch.
    private let zoomedOutArguments = ["-brewdesk.debug.initial-span", "45"]

    /// Polls `map-last-query` until its longitude differs from `before`.
    @MainActor
    private func waitForQueryToMove(
        _ app: XCUIApplication, from before: (lat: Double, lng: Double, radiusM: Int)
    ) -> (lat: Double, lng: Double, radiusM: Int)? {
        let deadline = Date().addingTimeInterval(wait)
        while Date() < deadline {
            if let current = lastQuery(app), abs(current.lng - before.lng) > 0.0001 { return current }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return nil
    }

    // MARK: - Tests

    /// First load must never show the pill — only a real pan/zoom can.
    @MainActor
    func testPillIsHiddenOnFirstLoad() throws {
        let app = launchFixtures()
        XCTAssertTrue(element(app, "map-header-card").waitForExistence(timeout: wait))
        // Give the initial camera settle + first load a moment, same
        // pattern `MapShelfDetentUITests` uses before asserting a resting
        // state.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(
            element(app, "map-search-area").exists,
            "the pill must not appear before the user has panned/zoomed"
        )
    }

    /// The core flow (bd#267): pan far enough → with NO tap, the exposed
    /// last-query center moves to the panned-to viewport, and the pill
    /// never shows.
    @MainActor
    func testPanAutoLoadsTheNewViewportWithoutAnyTap() throws {
        let app = launchFixtures()
        XCTAssertTrue(element(app, "map-header-card").waitForExistence(timeout: wait))
        Thread.sleep(forTimeInterval: 1.0)

        let lastQueryElement = element(app, "map-last-query")
        XCTAssertTrue(lastQueryElement.waitForExistence(timeout: wait))
        let before = try XCTUnwrap(lastQuery(app), "map-last-query did not expose a parseable value")

        panFarWest(app)

        let after = try XCTUnwrap(
            waitForQueryToMove(app, from: before),
            "panning to a new area never dispatched a query for it (before: \(before))"
        )
        // Dragging the map content west brings the area to the EAST into view.
        XCTAssertGreaterThan(after.lng, before.lng, "the new query should be centered on the panned-to area, east of the first")
        XCTAssertFalse(
            app.buttons["map-search-area"].exists,
            "the pill is a fallback only — a successful automatic load must not show it"
        )
        capture("auto-load-after-pan")
    }

    /// A small nudge stays inside the loaded viewport: no new query.
    @MainActor
    func testSmallPanDoesNotRefetch() throws {
        let app = launchFixtures()
        XCTAssertTrue(element(app, "map-header-card").waitForExistence(timeout: wait))
        Thread.sleep(forTimeInterval: 1.0)
        let before = try XCTUnwrap(lastQuery(app), "map-last-query did not expose a parseable value")

        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45))
            .press(
                forDuration: 0.1,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45)),
                withVelocity: .slow,
                thenHoldForDuration: 0.3
            )
        Thread.sleep(forTimeInterval: 2.5)

        let after = try XCTUnwrap(lastQuery(app), "map-last-query stopped exposing a parseable value")
        XCTAssertEqual(after.lng, before.lng, accuracy: 0.000001, "a small pan must not refetch")
        XCTAssertEqual(after.lat, before.lat, accuracy: 0.000001, "a small pan must not refetch")
        XCTAssertFalse(app.buttons["map-search-area"].exists)
    }

    /// The fallback: zoomed out past the auto-load limit, a pan does NOT
    /// fetch on its own — the pill appears instead, and tapping it
    /// dispatches the query, shows its progress state, then hides.
    @MainActor
    func testZoomedOutPanShowsPillAndTapRefetchesTheNewViewport() throws {
        let app = launchFixtures(extraArguments: zoomedOutArguments)
        XCTAssertTrue(element(app, "map-header-card").waitForExistence(timeout: wait))
        Thread.sleep(forTimeInterval: 1.0)

        let lastQueryElement = element(app, "map-last-query")
        XCTAssertTrue(lastQueryElement.waitForExistence(timeout: wait))
        let before = try XCTUnwrap(lastQuery(app), "map-last-query did not expose a parseable value")

        panFarWest(app)

        let pill = app.buttons["map-search-area"]
        XCTAssertTrue(pill.waitForExistence(timeout: wait), "zoomed out, panning far never offered the Search this area pill")
        let untouched = try XCTUnwrap(lastQuery(app))
        XCTAssertEqual(untouched.lng, before.lng, accuracy: 0.000001, "zoomed out past the limit, nothing may fetch on its own")
        capture("search-area-pill-visible-zoomed-out")

        pill.tap()

        // The pill either flips to its progress state briefly or has
        // already hidden by the time this reads it — both are correct
        // (the fixture scenario answers near-instantly); only a pill stuck
        // visible with no progress and no hide would be a bug, and the
        // waitForNonExistence below is what actually pins that down.
        XCTAssertTrue(
            pill.waitForNonExistence(timeout: wait),
            "the pill never hid after its own fetch settled"
        )

        let after = try XCTUnwrap(lastQuery(app), "map-last-query did not expose a parseable value after the tap")
        XCTAssertGreaterThan(
            abs(after.lng - before.lng), 0.0001,
            "Search this area tap did not dispatch a new query centered on the panned-to viewport"
            + " (before: \(before), after: \(after))"
        )

        capture("search-area-pill-post-tap")
    }

    /// bd#217 (TestFlight build 26 regression): the annotation planner is
    /// supposed to treat the pill's own frame as an exclusion rect once
    /// it's on screen (`CafeMapScreen.chromeExclusionRects`), but a
    /// candidate that lost specifically to that rect used to still render
    /// as a demoted `.dot` at the SAME coordinate — a small marker peeking
    /// out from under the pill, exactly what Bilal's screenshot showed.
    /// Only a real numbered teardrop is an `XCUIElement` `Button` this
    /// suite can even see (`.dot`/`.speck` are native `MapCircle` overlays
    /// with no button of their own) — the pin-label contract
    /// (`CafeMapScreen.pinLabel`) always contains a comma, which is enough
    /// to tell a marker button apart from every other button on screen.
    @MainActor
    func testNoAnnotationButtonIntersectsThePillAfterPan() throws {
        // bd#267: the pill only shows as a fallback now — zoomed out past
        // the auto-load limit is the deterministic way to get it on screen.
        let app = launchFixtures(extraArguments: zoomedOutArguments)
        XCTAssertTrue(element(app, "map-header-card").waitForExistence(timeout: wait))
        Thread.sleep(forTimeInterval: 1.0)

        panFarWest(app)

        let pill = app.buttons["map-search-area"]
        XCTAssertTrue(pill.waitForExistence(timeout: wait), "zoomed out, panning far never offered the Search this area pill")
        // Let the re-plan settle (the pill's own geometry read + the
        // resulting re-plan are each a separate render pass) before
        // reading marker frames.
        Thread.sleep(forTimeInterval: 1.0)

        let pillFrame = pill.frame
        capture("search-area-pill-clear-of-markers")

        let markerButtons = app.buttons.allElementsBoundByIndex.filter { $0.label.contains(",") }
        XCTAssertFalse(markerButtons.isEmpty, "test setup: fixtureOK must place at least one numbered teardrop on screen")
        for marker in markerButtons {
            XCTAssertFalse(
                pillFrame.intersects(marker.frame),
                "marker '\(marker.label)' at \(marker.frame) sits under the Search this area pill at \(pillFrame)"
            )
        }
    }
}
