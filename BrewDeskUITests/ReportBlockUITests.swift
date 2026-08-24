import XCTest

/// Report content + block contributor (brewdesk#48, Apple 1.2), attached to
/// the fullscreen photo viewer for community photos only — Google Places
/// photos are licensed content, not UGC. Scenario `communityPhotos`: photo 0
/// is the Google fixture photo, photo 1 the community photo by "Ada L."
/// (same fixture contract as PhotoBylineUITests). Blocking filters photo
/// fetches through `ContributorBlockStore` (in-memory under scenarios).
final class ReportBlockUITests: XCTestCase {
    private let wait: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", "communityPhotos",
            "-brewdesk.saved-venue-ids", "()",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    // brewdesk#117: detail now opens from the Spots tab's map/shelf (a
    // sheet), not a Nearby-list push — Nearby no longer exists.
    @MainActor
    private func openFixtureRoastersDetail(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["tab-spots"].waitForExistence(timeout: wait))
        app.tabBars.buttons["tab-spots"].tap()
        let pin = app.mapPin(named: "Fixture Roasters")
        XCTAssertTrue(pin.waitForExistence(timeout: wait))
        pin.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: wait))
    }

    @MainActor
    private func communityThumb(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Photo by Ada L.")
        ).firstMatch
    }

    @MainActor
    private func googleThumb(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label == %@", "Photo of Fixture Roasters")
        ).firstMatch
    }

    @MainActor
    private func openCommunityViewer(_ app: XCUIApplication) {
        openFixtureRoastersDetail(app)
        XCTAssertTrue(element(app, "venue-photo-strip").waitForExistence(timeout: wait))
        let thumb = communityThumb(app)
        XCTAssertTrue(thumb.waitForExistence(timeout: wait))
        thumb.tap()
        XCTAssertTrue(element(app, "photo-community-byline").waitForExistence(timeout: wait))
    }

    // MARK: - Report

    @MainActor
    func testReportCommunityPhotoFlow() {
        let app = launch()
        openCommunityViewer(app)

        element(app, "photo-moderation-menu").tap()
        XCTAssertTrue(app.buttons["Report Photo"].waitForExistence(timeout: wait))
        app.buttons["Report Photo"].tap()

        // Reason sheet: submit is gated on choosing a reason.
        XCTAssertTrue(element(app, "report-sheet").waitForExistence(timeout: wait))
        let submit = element(app, "report-submit")
        XCTAssertFalse(submit.isEnabled)

        element(app, "report-reason-inappropriate").tap()
        XCTAssertTrue(submit.isEnabled)
        submit.tap()

        XCTAssertTrue(element(app, "report-success").waitForExistence(timeout: wait))
        element(app, "report-done").tap()

        // Back on the (unchanged) viewer.
        XCTAssertTrue(element(app, "photo-community-byline").waitForExistence(timeout: wait))
    }

    // MARK: - Google photos are not reportable UGC

    @MainActor
    func testGooglePhotoViewerHasNoModerationMenu() {
        let app = launch()
        openFixtureRoastersDetail(app)

        XCTAssertTrue(element(app, "venue-photo-strip").waitForExistence(timeout: wait))
        let thumb = googleThumb(app)
        XCTAssertTrue(thumb.waitForExistence(timeout: wait))
        thumb.tap()

        XCTAssertTrue(element(app, "photo-attribution").waitForExistence(timeout: wait))
        XCTAssertFalse(element(app, "photo-moderation-menu").exists)
    }

    // MARK: - Block

    @MainActor
    func testBlockContributorHidesTheirPhotosOnNextFetch() {
        let app = launch()
        openCommunityViewer(app)

        element(app, "photo-moderation-menu").tap()
        XCTAssertTrue(app.buttons["Block Ada L."].waitForExistence(timeout: wait))
        app.buttons["Block Ada L."].tap()

        // Confirmation dialog → Block. The viewer dismisses immediately.
        let confirmBlock = app.buttons["Block"].firstMatch
        XCTAssertTrue(confirmBlock.waitForExistence(timeout: wait))
        confirmBlock.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: wait))

        // Re-enter the detail screen: the fresh photo fetch filters through
        // the block list — community photo gone, Google photo untouched.
        // Detail is a sheet from Spots (brewdesk#117) — swipe down to
        // dismiss it (no back button) and wait for Spots to actually be
        // back before reopening it.
        app.swipeDown()
        XCTAssertTrue(app.mapPins.firstMatch.waitForExistence(timeout: wait), "Spots did not survive the sheet dismiss")
        let pin = app.mapPin(named: "Fixture Roasters")
        XCTAssertTrue(pin.waitForExistence(timeout: wait))
        pin.waitUntilHittable()
        pin.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: wait))

        XCTAssertTrue(element(app, "venue-photo-strip").waitForExistence(timeout: wait))
        XCTAssertTrue(googleThumb(app).waitForExistence(timeout: wait))
        XCTAssertFalse(communityThumb(app).exists)
    }
}
