import XCTest

/// Contributor bylines (brewdesk#49): approved community photos show
/// "Photo by <display name>" in the strip and the fullscreen viewer — our own
/// attribution UI — while Google Places photos keep the unchanged Google
/// attribution (name + "View on Google Maps", viewer only). Fixture-driven via
/// `-UITestScenario communityPhotos` (see `ScenarioVenueService`): photo 0 is
/// the Google fixture photo, photo 1 the community photo by "Ada L.".
final class PhotoBylineUITests: XCTestCase {
    private let wait: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launchCommunityPhotos() -> XCUIApplication {
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

    /// The community thumbnail: its combined accessibility label carries the
    /// byline ("Photo of Fixture Roasters, Photo by Ada L."), which is also
    /// the seam the visual chip hangs off (`communityByline`).
    @MainActor
    private func communityThumb(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Photo by Ada L.")
        ).firstMatch
    }

    /// The Google thumbnail: a photo button with NO byline in its label.
    @MainActor
    private func googleThumb(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label == %@", "Photo of Fixture Roasters")
        ).firstMatch
    }

    // MARK: - Community photos (our attribution UI)

    @MainActor
    func testCommunityPhotoShowsBylineInStripAndViewer() {
        let app = launchCommunityPhotos()
        openFixtureRoastersDetail(app)

        // Strip: the community thumbnail carries the byline; the Google
        // thumbnail (also present in this scenario) does not.
        XCTAssertTrue(element(app, "venue-photo-strip").waitForExistence(timeout: wait))
        XCTAssertTrue(communityThumb(app).waitForExistence(timeout: wait))
        XCTAssertTrue(googleThumb(app).exists)

        // Fullscreen viewer: community byline, and no Google attribution UI.
        communityThumb(app).tap()
        XCTAssertTrue(element(app, "photo-community-byline").waitForExistence(timeout: wait))
        XCTAssertTrue(app.staticTexts["Photo by Ada L."].exists)
        XCTAssertFalse(element(app, "photo-attribution").exists)
        XCTAssertFalse(app.links["View on Google Maps"].exists)
    }

    // MARK: - Google photos (attribution unchanged)

    @MainActor
    func testGooglePhotoKeepsGoogleAttributionAndNoByline() {
        let app = launchCommunityPhotos()
        openFixtureRoastersDetail(app)

        XCTAssertTrue(element(app, "venue-photo-strip").waitForExistence(timeout: wait))
        let thumb = googleThumb(app)
        XCTAssertTrue(thumb.waitForExistence(timeout: wait))
        thumb.tap()

        // Unchanged pre-#49 contract (same anchor as DegradedStateTests'
        // viewer test): the Google attribution row with name + Maps link. The
        // row is a combined accessibility element, so the Link is not exposed
        // as a separate `links` element — match the label on any element type.
        XCTAssertTrue(element(app, "photo-attribution").waitForExistence(timeout: wait))
        XCTAssertTrue(app.staticTexts["Photo by Fixture Photographer"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "View on Google Maps"))
                .firstMatch.exists
        )
        XCTAssertFalse(element(app, "photo-community-byline").exists)
    }
}
