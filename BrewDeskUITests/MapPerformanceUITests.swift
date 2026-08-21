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

    // MARK: - Representation behavior (clusters → dots/pins → detail)

    /// At dataset scale the default zoom must show cluster pills, not one
    /// annotation per venue; tapping clusters zooms until individual venues
    /// appear, and tapping a venue still reaches the detail sheet.
    @MainActor
    func testClustersZoomToVenuesAndDetailTapThrough() throws {
        let app = launchManyVenues()

        let cluster = app.buttons.matching(identifier: "map-cluster").firstMatch
        XCTAssertTrue(
            cluster.waitForExistence(timeout: wait),
            "2,180 venues at default zoom should render as cluster pills"
        )

        // Each tap zooms one step in; individual venue annotations (labelled
        // "<name>, Work Fit <n>, <neighborhood>") must appear within a few.
        var zoomSteps = 0
        while zoomSteps < 6, !app.mapPins.firstMatch.exists {
            let pill = app.buttons.matching(identifier: "map-cluster").firstMatch
            guard pill.waitForExistence(timeout: 5) else { break }
            pill.tap()
            zoomSteps += 1
            Thread.sleep(forTimeInterval: 1.0)
        }

        let pin = app.mapPins.firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: wait), "zooming into clusters never yielded venue annotations")

        pin.tap()
        XCTAssertTrue(
            app.staticTexts["Workability"].waitForExistence(timeout: wait),
            "tapping a venue annotation no longer opens the detail sheet"
        )
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
    private func scriptedPan(_ app: XCUIApplication) {
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
        for (from, to) in pairs {
            window.coordinate(withNormalizedOffset: from)
                .press(
                    forDuration: 0.02,
                    thenDragTo: window.coordinate(withNormalizedOffset: to),
                    withVelocity: .fast,
                    thenHoldForDuration: 0.05
                )
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
