import XCTest

/// Store-build surface gate (brewdesk#67). The App Store submission binary
/// is an accountless app matching "Data Not Collected": no account card, no
/// report/block actions, no observation entry card. The gate is the
/// `STORE_SURFACE_GATED` build setting → `BDStoreSurfaceGated` Info.plist
/// key; these tests force it ON via the one-directional
/// `-UITestStoreSurfaceGated` launch argument (the same code path
/// `StoreSurface.isGated` reads) and prove the surface disappears, then run
/// the identical navigation ungated to prove the recipe finds the surface
/// when it should (so the negative assertions cannot pass vacuously).
///
/// brewdesk#117: the account card moved from a Saved-toolbar push into the
/// You tab (`AccountScreen` is now that tab's root), and the gating moved
/// with it — from hiding the entry link to hiding the card itself inside
/// the screen. `testGatedBuildHidesAccountCard` is the concrete proof of
/// the ticket's acceptance criterion that the gated You tab still reads as
/// a deliberate About surface (How scoring works, Contact & Content Rules,
/// Support/Privacy/Terms/credits/version all present) rather than
/// half-empty.
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
        XCTAssertTrue(app.savedTab.waitForExistence(timeout: wait))
        app.savedTab.tap()
        XCTAssertTrue(element(app, "saved-state-empty").waitForExistence(timeout: wait))
    }

    @MainActor
    private func openYouTab(_ app: XCUIApplication) {
        XCTAssertTrue(app.youTab.waitForExistence(timeout: wait))
        app.youTab.tap()
        XCTAssertTrue(app.navigationBars["You"].waitForExistence(timeout: wait))
    }

    // brewdesk#117: detail now opens from the Spots tab's map/shelf (a
    // sheet), not a Nearby-list push — Nearby no longer exists.
    @MainActor
    private func openFixtureRoastersDetail(_ app: XCUIApplication) {
        XCTAssertTrue(app.spotsTab.waitForExistence(timeout: wait))
        app.spotsTab.tap()
        let pin = app.mapPin(named: "Fixture Roasters")
        XCTAssertTrue(pin.waitForExistence(timeout: wait))
        pin.tap()
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: wait))
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
    func testGatedBuildHidesAccountCard() {
        let app = launch(gated: true)
        openYouTab(app)

        // The account card / sign-in form is gone...
        XCTAssertFalse(element(app, "account-mode-toggle").exists)
        XCTAssertFalse(element(app, "account-submit").exists)
        XCTAssertFalse(element(app, "account-signed-in").exists)

        // ...but the tab still reads as a deliberate About surface, not
        // half-empty (brewdesk#117 acceptance criterion): how-this-works +
        // legal/credits rows all survive the gate.
        XCTAssertTrue(element(app, "methodology-link").exists)
        XCTAssertTrue(element(app, "account-policies-entry").exists)
        XCTAssertTrue(app.staticTexts["BrewDesk"].exists)

        let osmCredit = element(app, "OpenStreetMap contributors")
        var swipes = 0
        while !osmCredit.exists, swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(osmCredit.exists)
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
        openYouTab(app)
        XCTAssertTrue(element(app, "account-mode-toggle").waitForExistence(timeout: wait))

        openFixtureRoastersDetail(app)
        openCommunityViewer(app)
        XCTAssertTrue(element(app, "photo-moderation-menu").waitForExistence(timeout: wait))
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: wait))

        swipeToDetailBottom(app)
        XCTAssertTrue(
            element(app, "observation-entry").exists,
            "Rate this visit entry not reachable on the detail screen"
        )
    }
}
