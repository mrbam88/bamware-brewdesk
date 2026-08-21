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

    @MainActor
    private func openFixtureRoastersDetail(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Nearby"].waitForExistence(timeout: wait))
        app.tabBars.buttons["Nearby"].tap()
        let row = app.staticTexts["Fixture Roasters"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: wait))
        row.tap()
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
        app.navigationBars["Details"].buttons.firstMatch.tap()
        let row = app.staticTexts["Fixture Roasters"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: wait))
        row.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: wait))

        XCTAssertTrue(element(app, "venue-photo-strip").waitForExistence(timeout: wait))
        XCTAssertTrue(googleThumb(app).waitForExistence(timeout: wait))
        XCTAssertFalse(communityThumb(app).exists)
    }
}
