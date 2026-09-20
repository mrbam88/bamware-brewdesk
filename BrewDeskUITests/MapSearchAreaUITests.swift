import XCTest

/// bd#192 ("Search this area"): the map now derives its fetch from the
/// visible viewport instead of one fixed 2.5 km/100-venue query — this pill
/// is the trigger for a NEW query once a pan/zoom moves the camera far
/// enough that the loaded venues may no longer cover what's on screen.
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
    private func launchFixtures() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", "fixtureOK",
            // A real CoreLocation fix landing mid-test (e.g. a simulator
            // with location previously granted from local dev work) would
            // fight this suite's own viewport updates via
            // `DiscoveryRootView`'s `updateCenterIfNeeded` short-circuit —
            // pin `.notDetermined` so every center/radius change this file
            // observes came from the pill/pan under test, not GPS.
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
    /// ends up well past the pill's 35%-of-loaded-radius threshold — a
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

    // MARK: - Tests

    /// First load must never show the pill (the ticket's own exception) —
    /// only a real pan/zoom does.
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

    /// The core flow: pan far enough → pill appears → tap → pill shows a
    /// progress state, then hides → the exposed last-query center/radius
    /// now matches the panned-to viewport, not the original load.
    @MainActor
    func testPanRevealsPillAndTapRefetchesTheNewViewport() throws {
        let app = launchFixtures()
        XCTAssertTrue(element(app, "map-header-card").waitForExistence(timeout: wait))
        Thread.sleep(forTimeInterval: 1.0)

        let lastQueryElement = element(app, "map-last-query")
        XCTAssertTrue(lastQueryElement.waitForExistence(timeout: wait))
        let before = try XCTUnwrap(lastQuery(app), "map-last-query did not expose a parseable value")

        panFarWest(app)

        let pill = app.buttons["map-search-area"]
        XCTAssertTrue(pill.waitForExistence(timeout: wait), "panning far enough never showed the Search this area pill")
        capture("search-area-pill-visible-after-pan")

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
        let app = launchFixtures()
        XCTAssertTrue(element(app, "map-header-card").waitForExistence(timeout: wait))
        Thread.sleep(forTimeInterval: 1.0)

        panFarWest(app)

        let pill = app.buttons["map-search-area"]
        XCTAssertTrue(pill.waitForExistence(timeout: wait), "panning far enough never showed the Search this area pill")
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
