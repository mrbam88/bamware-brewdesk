import XCTest

/// bd#185: the custom `LocateMeButton` that replaced the stock, barely
/// visible `MapUserLocationButton()`.
///
/// The authorized case needs a REAL CoreLocation fix, not one of the
/// `-UITestLocation*` fixture seams (those only pin `authorizationStatus`;
/// `LocationService` still reads an actual coordinate from
/// `CLLocationUpdate.liveUpdates()`). `Foundation.Process` isn't available
/// inside an iOS UI-test runner, so the simulator's location privacy and
/// simulated GPS fix have to be set from the HOST side before `xcodebuild
/// test` runs — see `scripts/prepare_locate_button_uitests.sh`, which the CI
/// step (and this file's own doc) both call out. Locally:
///
///   xcrun simctl privacy <udid> grant location io.bamware.brewdesk
///   xcrun simctl location <udid> set 40.729100,-73.996500
///
/// before running `testAuthorizedTapCentersOnSimulatedLocation`. The denied
/// case needs no simulator setup — it uses the same `-UITestLocationDenied`
/// fixture seam `DegradedStateTests` already relies on.
final class MapLocateButtonUITests: XCTestCase {
    private let wait: TimeInterval = 15
    /// `xcrun simctl location <udid> set 40.729100,-73.996500` (Union
    /// Square-adjacent — inside `fixtureOK`'s coverage area).
    private let simulatedLat = 40.7291
    private let simulatedLng = -73.9965
    /// Loose enough to absorb simulator GPS jitter and the walking-zoom
    /// span's rounding, tight enough to prove the camera actually moved to
    /// the simulated fix rather than staying on the Union Square fallback
    /// (~700m away) or some other stale center.
    private let centeredToleranceMeters = 200.0

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Authorized: tap centers the camera

    @MainActor
    func testAuthorizedTapCentersOnSimulatedLocation() throws {
        let app = XCUIApplication()
        // No `-UITestLocation*` seam: this exercises the real
        // authorized-with-a-fix rail, which is the one the original bug
        // report ("the button's not working") was actually about.
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", "fixtureOK",
            "-brewdesk.saved-venue-ids", "()",
        ]
        app.launch()

        let locate = app.buttons["map-locate-me"]
        guard locate.waitForExistence(timeout: wait) else {
            throw XCTSkip("locate button never appeared — device location privacy likely not authorized for io.bamware.brewdesk; see this file's header for the simctl setup this test needs")
        }

        let center = app.descendants(matching: .any)["map-camera-center"]
        XCTAssertTrue(center.waitForExistence(timeout: wait), "map camera center accessibility element missing")

        locate.tap()

        // Camera animation is `.snappy`; poll rather than a fixed sleep so
        // this isn't racing the animation's exact duration.
        let deadline = Date().addingTimeInterval(wait)
        var closestDistance = Double.greatestFiniteMagnitude
        while Date() < deadline {
            if let coordinate = Self.parseCoordinate(center.value as? String) {
                let distance = Self.metersBetween(
                    coordinate.lat, coordinate.lng, simulatedLat, simulatedLng
                )
                closestDistance = min(closestDistance, distance)
                if distance <= centeredToleranceMeters { break }
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertLessThanOrEqual(
            closestDistance, centeredToleranceMeters,
            "locate tap never centered the map within \(centeredToleranceMeters)m of the simulated fix (closest: \(closestDistance)m) — camera-center value: \(center.value ?? "nil")"
        )

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "locate-button-authorized-centered"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Denied: tap shows the Settings alert

    @MainActor
    func testDeniedTapShowsSettingsAlert() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", "fixtureOK",
            "-UITestLocationDenied",
        ]
        app.launch()

        let locate = app.buttons["map-locate-me"]
        XCTAssertTrue(locate.waitForExistence(timeout: wait), "locate button missing in denied state")

        locate.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: wait), "denied tap did not show the Settings alert")
        XCTAssertTrue(alert.buttons["Open Settings"].exists)
        XCTAssertTrue(alert.buttons["Cancel"].exists)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "locate-button-denied-alert"
        attachment.lifetime = .keepAlways
        add(attachment)

        alert.buttons["Cancel"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: wait))
    }

    // MARK: - Helpers

    /// `"lat,lng"` (see `CafeMapScreen.cameraCenterAccessibilityValue`).
    private static func parseCoordinate(_ raw: String?) -> (lat: Double, lng: Double)? {
        guard let raw else { return nil }
        let parts = raw.components(separatedBy: ",")
        guard parts.count == 2, let lat = Double(parts[0]), let lng = Double(parts[1]) else { return nil }
        return (lat, lng)
    }

    /// Haversine distance in meters — mirrors `VenuesModel.metersBetween`'s
    /// shape, duplicated here rather than shared since UI tests can't import
    /// the app's package target.
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
