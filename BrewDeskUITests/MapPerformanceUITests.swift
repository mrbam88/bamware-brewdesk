import XCTest

/// Map scrolling performance and representation behavior (brewdesk#54).
///
/// Runs against the deterministic `manyVenues` fixture scenario (2,180 venues,
/// the live dataset's size) so measurements are reproducible offline in Debug
/// and Release. Frame timing comes from the in-app CADisplayLink recorder
/// (`-UITestFrameStats`, see `MapFrameStats.swift`); the parsed numbers are
/// attached to the test log as the PR's on-sim evidence. The headline is
/// hitch TIME for a fixed script (brewdesk#211), with the count of map body
/// evaluations and marker re-plans beside it.
final class MapPerformanceUITests: XCTestCase {
    private let wait: TimeInterval = 15

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Hitch time (the #211 measurement)

    /// Neighbourhood zoom (3.3 m/pt, what a first GPS fix opens at): rated
    /// venues are numbered teardrops, each a hosted SwiftUI annotation.
    @MainActor
    func testScriptedPanHitchTime() throws {
        let stats = try measureScriptedPan(metersPerPoint: "3.3", tag: "MAP-PERF")
        XCTAssertGreaterThan(stats["teardrops"].flatMap(Int.init) ?? 0, 0, "neighbourhood zoom drew no teardrop pins")
    }

    /// City zoom (9 m/pt, past the 7.2 m/pt teardrop threshold): every venue
    /// is a plain dot, a native `MapCircle`. `-brewdesk.debug.initial-span`
    /// is METRES PER POINT; the old `0.05` asked for the closest zoom there
    /// is and measured 220 teardrops instead (brewdesk#211, #275).
    @MainActor
    func testScriptedPanHitchTimeAtDotZoom() throws {
        let stats = try measureScriptedPan(metersPerPoint: "9", tag: "MAP-PERF-DOTS")
        XCTAssertEqual(stats["teardrops"].flatMap(Int.init), 0, "dot zoom still drew teardrop pins")
    }

    /// The measurement itself. Everything that used to make the number move
    /// between runs of one binary is pinned down:
    /// - the same eight drags every time (same points, same velocity), four
    ///   out and four back, so the camera ends where it started;
    /// - a fixed pause after each, long enough for the camera to rest, the
    ///   markers to be re-planned and the auto-load (bd#267) to answer, so
    ///   every run does the same amount of work;
    /// - one warm-up pair first, discarded (first-use tile and glyph work);
    /// - frames count only from the first measured drag to one second after
    ///   the last (`MapPerfProbe`), and the headline is milliseconds, not a
    ///   ratio over however long XCUITest happened to idle.
    @MainActor
    private func measureScriptedPan(metersPerPoint: String, tag: String) throws -> [String: String] {
        let app = launchManyVenues(extra: ["-UITestFrameStats", "-brewdesk.debug.initial-span", metersPerPoint])
        let hud = app.descendants(matching: .any)["frame-stats"].firstMatch
        XCTAssertTrue(hud.waitForExistence(timeout: wait), "frame-stats HUD missing")
        waitForAnnotations(hud, timeout: wait)
        Thread.sleep(forTimeInterval: 1.5)

        scriptedPan(app, drags: 2)
        Thread.sleep(forTimeInterval: 1.5)
        // Tapping the HUD zeroes every counter; the window opens on the
        // first drag after it.
        hud.tap()

        scriptedPan(app, drags: 8)

        // Past the window's one-second tail plus a publish interval.
        Thread.sleep(forTimeInterval: 2.0)
        let label = hud.label
        let stats = parse(label)
        let attachment = XCTAttachment(string: "\(tag) \(label)")
        attachment.name = "map-pan-frame-stats"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("\(tag) \(label)")

        XCTAssertGreaterThan(stats["windowMs"].flatMap(Double.init) ?? 0, 5_000, "measurement window never closed: \(label)")
        let stallMs = try XCTUnwrap(stats["stallMs"].flatMap(Double.init), "frame stats label not parseable: \(label)")
        // Loose bound on the time spent in frames of 100 ms or more: catches
        // a sustained stutter without flaking on a busy machine (`hitchMs`,
        // which also counts 34-99 ms frames, doubles when another build is
        // running; `stallMs` does not). The PR carries the exact numbers.
        XCTAssertLessThan(stallMs, Self.stallBudgetMs, "map pan spent too long in stalled frames: \(label)")
        return stats
    }

    /// Ceiling on stall time for the eight-drag script, in milliseconds.
    private static let stallBudgetMs = 8_000.0

    // MARK: - Representation behavior (markers → detail, bd#212)

    /// bd#212: no cluster/stack representation exists any more — at ANY
    /// zoom (including default), the 2,180-venue `manyVenues` fixture draws
    /// one marker per venue (teardrop, demoted dot, or unrated speck), never
    /// a count group. Tapping a rated venue's marker must still reach its
    /// detail sheet. Replaces the old `testClustersZoomToVenuesAndDetailTapThrough`
    /// (its zoom-stepping loop no longer applies — there's nothing to zoom
    /// past).
    @MainActor
    func testTappingAVenueMarkerOpensDetail() throws {
        let app = launchManyVenues()

        let pin = app.mapPins.firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: wait), "2,180 venues at default zoom rendered no venue markers")
        XCTAssertFalse(
            app.buttons.matching(identifier: "map-cluster").firstMatch.exists,
            "bd#212: no cluster/stack marker may exist anywhere in the app"
        )

        pin.tap()
        XCTAssertTrue(
            app.staticTexts["Workability"].waitForExistence(timeout: wait),
            "tapping a venue marker no longer opens the detail sheet"
        )
    }

    // MARK: - Motion (bd#212 VERIFY step — pinch smoothness, video-captured)

    /// Not a frame-timing measurement — this is the seam a host-side
    /// `xcrun simctl io <udid> recordVideo` wraps around while it runs, so a
    /// human (or a contact-sheet review) can watch that markers stay locked
    /// to their streets through a real pinch gesture and that sizes settle
    /// smoothly rather than flashing/disappearing. Five zoom-in/zoom-out
    /// pinches, each held a beat so `.onMapCameraChange(frequency: .onEnd)`
    /// actually fires and the camera has time to visibly settle between
    /// direction changes.
    @MainActor
    func testPinchZoomStaysSmoothAndMarkersStayAttached() throws {
        let app = launchManyVenues()
        XCTAssertTrue(app.mapPins.firstMatch.waitForExistence(timeout: wait), "map never rendered markers before the pinch")

        // The MAP, not the window (brewdesk#275): a window-wide pinch puts a
        // finger on the tab bar, which since the Ask tab shipped switches
        // tabs and leaves no map to find markers on.
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: wait), "no map element to pinch")
        for _ in 0..<5 {
            map.pinch(withScale: 3, velocity: 1.2)
            Thread.sleep(forTimeInterval: 0.6)
            map.pinch(withScale: 0.33, velocity: -1.2)
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(app.tabBars.buttons["Spots"].isSelected, "the pinch left the Spots tab")

        // The map (and its markers) must still be alive and interactive
        // after the gesture sequence — a real regression here would leave
        // the map frozen or the marker layer empty.
        XCTAssertTrue(app.mapPins.firstMatch.waitForExistence(timeout: wait), "map lost its markers after pinching")
    }

    // MARK: - Helpers

    @MainActor
    private func launchManyVenues(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", "manyVenues",
        ] + extra
        app.launch()
        return app
    }

    /// Annotation count is published on the HUD label (`annotations=N`).
    @MainActor
    private func waitForAnnotations(_ hud: XCUIElement, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let count = parse(hud.label)["annotations"].flatMap(Int.init), count > 0 { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTFail("map never rendered annotations: \(hud.label)")
    }

    /// Identical fast drags across the map, alternately right-to-left and
    /// left-to-right along one line between the search header and the
    /// discovery shelf, with a fixed pause after each.
    @MainActor
    private func scriptedPan(_ app: XCUIApplication, drags: Int) {
        let window = app.windows.firstMatch
        let left = window.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.46))
        let right = window.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.46))
        for index in 0..<drags {
            let (from, to) = index.isMultiple(of: 2) ? (right, left) : (left, right)
            from.press(forDuration: 0.02, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0.05)
            Thread.sleep(forTimeInterval: 1.2)
        }
    }

    private func parse(_ label: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in label.components(separatedBy: ";") {
            let parts = pair.components(separatedBy: "=")
            guard parts.count == 2 else { continue }
            result[parts[0]] = parts[1]
        }
        return result
    }
}
