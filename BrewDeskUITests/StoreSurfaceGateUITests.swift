import XCTest

/// Store-build surface gate (brewdesk#67). The App Store submission binary
/// is an accountless app matching "Data Not Collected": no Account entry,
/// no report/block actions, no observation entry card. The gate is the
/// `STORE_SURFACE_GATED` build setting → `BDStoreSurfaceGated` Info.plist
/// key; these tests force it ON via the one-directional
/// `-UITestStoreSurfaceGated` launch argument (the same code path
/// `StoreSurface.isGated` reads) and prove the surface disappears, then run
/// the identical navigation ungated to prove the recipe finds the surface
/// when it should (so the negative assertions cannot pass vacuously).
final class StoreSurfaceGateUITests: XCTestCase {
    private let wait: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launch(gated: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", "communityPhotos",
            "-brewdesk.saved-venue-ids", "()",
        ]
        if gated {
            app.launchArguments.append("-UITestStoreSurfaceGated")
        }
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func openSavedTab(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Saved"].waitForExistence(timeout: wait))
        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(element(app, "saved-state-empty").waitForExistence(timeout: wait))
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

    /// Same fixture contract as ReportBlockUITests: photo 1 is the community
    /// photo by "Ada L.".
    @MainActor
    private func openCommunityViewer(_ app: XCUIApplication) {
        XCTAssertTrue(element(app, "venue-photo-strip").waitForExistence(timeout: wait))
        let thumb = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Photo by Ada L.")
        ).firstMatch
        XCTAssertTrue(thumb.waitForExistence(timeout: wait))
        thumb.tap()
        XCTAssertTrue(element(app, "photo-community-byline").waitForExistence(timeout: wait))
    }

    /// Swipe the detail scroll to the bottom, where the observation entry
    /// card lives (same recipe as ObservationFormUITests).
    @MainActor
    private func swipeToDetailBottom(_ app: XCUIApplication) {
        let entry = element(app, "observation-entry")
        var swipes = 0
        while !(entry.exists && entry.isHittable), swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
    }

    // MARK: - Gated: none of the store-gated UI exists

    @MainActor
    func testGatedBuildHidesAccountEntry() {
        let app = launch(gated: true)
        openSavedTab(app)

        // The toolbar itself still renders — Import survives the gate —
        // so the missing Account entry is not a missing toolbar.
        XCTAssertTrue(element(app, "import-saved-entry").waitForExistence(timeout: wait))
        XCTAssertFalse(element(app, "account-entry").exists)
    }

    @MainActor
    func testGatedBuildHidesObservationEntryCard() {
        let app = launch(gated: true)
        openFixtureRoastersDetail(app)

        swipeToDetailBottom(app)
        XCTAssertFalse(element(app, "observation-entry").exists)
        XCTAssertFalse(element(app, "observation-section").exists)
    }

    @MainActor
    func testGatedBuildHidesPhotoModerationMenu() {
        let app = launch(gated: true)
        openFixtureRoastersDetail(app)
        openCommunityViewer(app)

        // Byline attribution survives (it is required credit, not UGC
        // moderation surface); the report/block menu is gone.
        XCTAssertFalse(element(app, "photo-moderation-menu").exists)
        XCTAssertFalse(element(app, "photo-report-entry").exists)
        XCTAssertFalse(element(app, "photo-block-entry").exists)
    }

    // MARK: - Ungated control: identical navigation finds every surface

    @MainActor
    func testUngatedBuildKeepsAllSurfaces() {
        let app = launch(gated: false)

        openSavedTab(app)
        XCTAssertTrue(element(app, "account-entry").waitForExistence(timeout: wait))

        openFixtureRoastersDetail(app)
        openCommunityViewer(app)
        XCTAssertTrue(element(app, "photo-moderation-menu").waitForExistence(timeout: wait))
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: wait))

        swipeToDetailBottom(app)
        XCTAssertTrue(
            element(app, "observation-entry").exists,
            "Rate this visit entry not reachable on the detail screen"
        )
    }
}
