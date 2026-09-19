import XCTest

/// bd#198 regression: Bilal on TestFlight build 22 — "If I zoom into a
/// neighborhood and I hit 'Search this area,' it actually defaults back to
/// my location, the GPS of the phone." Root cause: `VenuesModel` had no
/// memory of why its centre last changed, so a passive GPS tick
/// (`DiscoveryRootView`'s `.task(id: request)`/`.onChange(of:
/// locationService.location)`) could silently overwrite a viewport the user
/// had just explored via "Search this area" — every later GPS tick did the
/// same, snapping the camera straight back (`CafeMapScreen.applyCenterChange()`).
///
/// `MapSearchAreaUITests` pins location to `.notDetermined` specifically to
/// keep GPS out of the picture, and `MapLocateButtonUITests`'s authorized
/// case needs a real simulated fix provisioned from the HOST side before
/// `xcodebuild test` runs (and skips outright otherwise) — neither proves
/// this bug. `-brewdesk.uitest-fixed-location` (bd#198) delivers an
/// authorized fix immediately and keeps re-delivering it roughly once a
/// second, so this suite can prove the fix deterministically in CI without
/// any `simctl` host setup.
final class MapSearchAreaGPSRegressionUITests: XCTestCase {
    private let wait: TimeInterval = 15
    /// Union Square-adjacent — inside `fixtureOK`'s coverage area, matching
    /// `MapLocateButtonUITests`'s simulated fix.
    private let fixedLat = 40.7291
    private let fixedLng = -73.9965

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launchWithFixedLocation() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", "fixtureOK",
            "-brewdesk.uitest-fixed-location", "\(fixedLat)|\(fixedLng)",
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

    /// Same shape as `MapSearchAreaUITests.panFarWest` — several fast,
    /// same-direction drags so the settled centre ends up well past both
    /// the pill's own threshold and the ~2 km this test asserts.
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

    /// Mirrors `VenuesModel.metersBetween` — UI tests can't import the app's
    /// package target.
    private static func metersBetween(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let earthRadiusM = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return earthRadiusM * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Test

    /// Pan ~2 km away from the fixed GPS fix, tap "Search this area", and
    /// confirm `map-last-query` reflects the PANNED centre, not the GPS
    /// fix — immediately after the tap, and still after 3s of further
    /// location ticks (`-brewdesk.uitest-fixed-location` re-delivers the
    /// same fix roughly once a second). Must FAIL on origin/main (before
    /// bd#198's fix) and PASS on the fix branch.
    @MainActor
    func testSearchThisAreaSurvivesFurtherLocationTicks() throws {
        let app = launchWithFixedLocation()
        XCTAssertTrue(element(app, "map-header-card").waitForExistence(timeout: wait))
        // Let the cold-start fix land and settle before panning.
        Thread.sleep(forTimeInterval: 1.5)

        panFarWest(app)

        let pill = app.buttons["map-search-area"]
        XCTAssertTrue(pill.waitForExistence(timeout: wait), "panning far enough never showed the Search this area pill")
        capture("gps-regression-pill-visible-after-pan")

        pill.tap()
        XCTAssertTrue(pill.waitForNonExistence(timeout: wait), "the pill never hid after its own fetch settled")

        let panned = try XCTUnwrap(lastQuery(app), "map-last-query did not expose a parseable value after the tap")
        let distanceFromFix = Self.metersBetween(panned.lat, panned.lng, fixedLat, fixedLng)
        XCTAssertGreaterThan(
            distanceFromFix, 1_000,
            "the panned-to query should land well away from the GPS fix (got \(distanceFromFix)m) — "
            + "the pan/tap itself didn't move the query far enough for this test to be meaningful"
        )
        capture("gps-regression-query-after-search-this-area")

        // The regression: further GPS ticks (the fixture re-delivers the
        // same fix ~once a second) must NOT overwrite the explored
        // viewport. Poll for 3s so this isn't just racing one tick.
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let current = try XCTUnwrap(lastQuery(app), "map-last-query stopped exposing a parseable value")
            XCTAssertEqual(
                current.lat, panned.lat, accuracy: 0.0001,
                "a GPS tick snapped the map back to the phone's location after \"Search this area\" (bd#198)"
            )
            XCTAssertEqual(
                current.lng, panned.lng, accuracy: 0.0001,
                "a GPS tick snapped the map back to the phone's location after \"Search this area\" (bd#198)"
            )
            Thread.sleep(forTimeInterval: 0.3)
        }

        capture("gps-regression-query-after-3s-of-ticks")
    }
}
