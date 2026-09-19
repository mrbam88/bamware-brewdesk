import XCTest

/// The one dedicated UI test for the cold-launch reveal
/// (bamware-brewdesk#186). Every other UI test skips the reveal outright
/// (`isUITestRun` gates it off in `RootView`) so it never races the rest of
/// the suite; `-UITestForceLaunchReveal` is the seam that turns it back on
/// just here.
final class LaunchRevealUITests: XCTestCase {
    @MainActor
    func testLaunchRevealDisappearsAndMainUIBecomesHittable() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestForceLaunchReveal", "-UITestSkipGates"]
        app.launch()

        // Not asserted present first: by the time XCUITest finishes
        // attaching its automation session (routinely 2-4s against this
        // simulator, longer than the reveal's own 1.2s hard cap), the
        // overlay may already be gone — that's a passing outcome too, not
        // a bug. What actually matters is that it's never still there
        // after the spec's promised window.
        let overlay = app.descendants(matching: .any)["launch-reveal-overlay"]
        let overlayGone = NSPredicate(format: "exists == false")
        _ = expectation(for: overlayGone, evaluatedWith: overlay, handler: nil)
        waitForExpectations(timeout: 1.5)

        // The real UI underneath was never blocked by the overlay — the
        // tab bar is hittable as soon as the overlay clears.
        XCTAssertTrue(app.spotsTab.waitForExistence(timeout: 2))
        XCTAssertTrue(app.spotsTab.isHittable)
        XCTAssertTrue(app.savedTab.isHittable)
        XCTAssertTrue(app.youTab.isHittable)
    }
}
