import XCTest

/// Map scrolling performance and representation behavior (brewdesk#54).
///
/// Runs against the deterministic `manyVenues` fixture scenario (2,180 venues,
/// the live dataset's size) so measurements are reproducible offline in Debug
/// and Release. Frame timing comes from the in-app CADisplayLink recorder
/// (`-UITestFrameStats`, see `MapFrameStats.swift`); the parsed numbers are
/// attached to the test log as the PR's on-sim evidence.
final class MapPerformanceUITests: XCTestCase {
    private let wait: TimeInterval = 15

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Frame timing (the #54 measurement)

    @MainActor
    func testScriptedPanFrameTiming() throws {
        let app = launchManyVenues(extra: ["-UITestFrameStats"])
        let hud = app.descendants(matching: .any)["frame-stats"].firstMatch
        XCTAssertTrue(hud.waitForExistence(timeout: wait), "frame-stats HUD missing")

        // Wait until the fixture set has actually rendered annotations.
        waitForAnnotations(hud, timeout: wait)

        // Let load-time work settle, then zero the counters so the numbers
        // cover only the scripted pan.
        Thread.sleep(forTimeInterval: 1.5)
        hud.tap()

        // NOTE: pass `hud:` to log per-drag annotation counts when debugging
        // representation churn — the extra accessibility snapshots perturb the
        // measurement (~1% hitch time), so the measured run keeps them off.
        scriptedPan(app)

        // One publish interval so the final counters land in the label.
        Thread.sleep(forTimeInterval: 0.5)
        let stats = parse(hud.label)
        let attachment = XCTAttachment(string: "map pan frame stats: \(hud.label)")
        attachment.name = "map-pan-frame-stats"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("MAP-PERF \(hud.label)")

        let frames = stats["frames"].flatMap(Double.init) ?? 0
        XCTAssertGreaterThan(frames, 100, "recorder measured too few frames to be meaningful")
        let hitchRatio = stats["hitchRatio"].flatMap(Double.init)
        XCTAssertNotNil(hitchRatio, "frame stats label not parseable: \(hud.label)")
        // Loose bound: catches sustained stutter without flaking on one-off
        // simulator scheduling blips. The PR carries the exact numbers.
        XCTAssertLessThan(hitchRatio ?? 1, 0.20, "map pan dropped too much frame time: \(hud.label)")
    }

    /// bd#212: the old "dot zoom" measurement tapped a cluster pill to zoom
    /// one representation step in; clusters no longer exist. The design's
    /// own "dot zoom" is now literal — `-brewdesk.debug.initial-span` opens
    /// the camera wide enough (>= 0.045°) that every rated venue in the
    /// 2,180-venue `manyVenues` fixture draws as a plain 4pt dot with no
    /// number, the exact "many small dots" density #211's regression
    /// profiled.
    @MainActor
    func testScriptedPanFrameTimingAtDotZoom() throws {
        let app = launchManyVenues(extra: ["-UITestFrameStats", "-brewdesk.debug.initial-span", "0.05"])
        let hud = app.descendants(matching: .any)["frame-stats"].firstMatch
        XCTAssertTrue(hud.waitForExistence(timeout: wait), "frame-stats HUD missing")
        waitForAnnotations(hud, timeout: wait)

        Thread.sleep(forTimeInterval: 1.5)
        hud.tap()

        scriptedPan(app)

        Thread.sleep(forTimeInterval: 0.5)
        let stats = parse(hud.label)
        let attachment = XCTAttachment(string: "dot-zoom pan frame stats: \(hud.label)")
        attachment.name = "map-pan-frame-stats-dot-zoom"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("MAP-PERF-DOTS \(hud.label)")

        let frames = stats["frames"].flatMap(Double.init) ?? 0
        XCTAssertGreaterThan(frames, 100, "recorder measured too few frames to be meaningful")
        let hitchRatio = stats["hitchRatio"].flatMap(Double.init)
        XCTAssertNotNil(hitchRatio, "frame stats label not parseable: \(hud.label)")
        // Loose bound: catches sustained stutter without flaking on one-off
        // simulator scheduling blips. The PR carries the exact numbers
        // against the ticket's ≤0.12 target.
        XCTAssertLessThan(hitchRatio ?? 1, 0.20, "dot-zoom pan dropped too much frame time: \(hud.label)")
    }

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

        let map = app.windows.firstMatch
        for _ in 0..<5 {
            map.pinch(withScale: 3, velocity: 1.2)
            Thread.sleep(forTimeInterval: 0.6)
            map.pinch(withScale: 0.33, velocity: -1.2)
            Thread.sleep(forTimeInterval: 0.6)
        }

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

    /// Eight fast drags across the map body — horizontal and vertical, kept
    /// between the search header and the discovery shelf.
    @MainActor
    private func scriptedPan(_ app: XCUIApplication, hud: XCUIElement? = nil) {
        let window = app.windows.firstMatch
        let pairs: [(CGVector, CGVector)] = [
            (CGVector(dx: 0.80, dy: 0.48), CGVector(dx: 0.15, dy: 0.48)),
            (CGVector(dx: 0.15, dy: 0.52), CGVector(dx: 0.80, dy: 0.52)),
            (CGVector(dx: 0.50, dy: 0.58), CGVector(dx: 0.50, dy: 0.40)),
            (CGVector(dx: 0.50, dy: 0.40), CGVector(dx: 0.50, dy: 0.58)),
            (CGVector(dx: 0.80, dy: 0.45), CGVector(dx: 0.20, dy: 0.55)),
            (CGVector(dx: 0.20, dy: 0.55), CGVector(dx: 0.80, dy: 0.45)),
            (CGVector(dx: 0.75, dy: 0.50), CGVector(dx: 0.25, dy: 0.50)),
            (CGVector(dx: 0.25, dy: 0.50), CGVector(dx: 0.75, dy: 0.50)),
        ]
        for (index, (from, to)) in pairs.enumerated() {
            window.coordinate(withNormalizedOffset: from)
                .press(
                    forDuration: 0.02,
                    thenDragTo: window.coordinate(withNormalizedOffset: to),
                    withVelocity: .fast,
                    thenHoldForDuration: 0.05
                )
            if let hud {
                // Representation flapping shows up as annotation-count swings.
                print("MAP-PERF-DRAG \(index) \(parse(hud.label)["annotations"] ?? "?")")
            }
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
