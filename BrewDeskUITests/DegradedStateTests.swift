import XCTest

/// Every screen under every failure a reviewer can provoke shows an intentional
/// state — never a blank view or a spinner with no exit. Fixture-driven via
/// `-UITestScenario` (see `ScenarioVenueService`); no live API involved, so
/// these run the same in Debug and Release, online or offline.
final class DegradedStateTests: XCTestCase {
    private let wait: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launch(
        _ scenario: String,
        savedIDs: String = "()",
        extra: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", scenario,
            "-brewdesk.saved-venue-ids", savedIDs,
        ] + extra
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func openNearby(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Nearby"].waitForExistence(timeout: wait))
        app.tabBars.buttons["Nearby"].tap()
    }

    @MainActor
    private func openSaved(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Saved"].waitForExistence(timeout: wait))
        app.tabBars.buttons["Saved"].tap()
    }

    @MainActor
    private func openFixtureRoastersDetail(_ app: XCUIApplication) {
        openNearby(app)
        let row = app.staticTexts["Fixture Roasters"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: wait))
        row.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: wait))
    }

    // MARK: - Map

    @MainActor
    func testMapEngineDownShowsRetry() {
        let app = launch("engineDown")
        XCTAssertTrue(element(app, "map-state-error").waitForExistence(timeout: wait))
        XCTAssertTrue(app.buttons["map-retry"].exists)

        app.buttons["map-retry"].tap()
        // Engine still down: the same intentional state, no crash, no blank.
        XCTAssertTrue(element(app, "map-state-error").waitForExistence(timeout: wait))
    }

    @MainActor
    func testMapEmptyVenuesOffersBrowseNYC() {
        let app = launch("emptyVenues")
        XCTAssertTrue(element(app, "map-state-empty").waitForExistence(timeout: wait))
        XCTAssertTrue(app.buttons["map-browse-nyc"].exists)
        XCTAssertFalse(element(app, "map-state-error").exists)
    }

    @MainActor
    func testMapSlowShowsLoadingThenContent() {
        let app = launch("slow")
        XCTAssertTrue(element(app, "map-state-loading").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["3 work cafés"].waitForExistence(timeout: 20))
        XCTAssertFalse(element(app, "map-state-loading").exists)
    }

    @MainActor
    func testMapLocationDeniedShowsBannerAndContent() {
        let app = launch("fixtureOK", extra: ["-UITestLocationDenied"])
        XCTAssertTrue(element(app, "location-denied-banner").waitForExistence(timeout: wait))
        XCTAssertTrue(app.buttons["location-open-settings"].exists)
        // Content still renders: denied location is a banner, not a wall.
        XCTAssertTrue(app.staticTexts["3 work cafés"].waitForExistence(timeout: wait))
    }

    // MARK: - List

    @MainActor
    func testListEngineDownShowsRetry() {
        let app = launch("engineDown")
        openNearby(app)
        XCTAssertTrue(element(app, "list-state-error").waitForExistence(timeout: wait))
        XCTAssertTrue(app.buttons["list-retry"].exists)
    }

    @MainActor
    func testListOfflineShowsTheSameRetryState() {
        let app = launch("offline")
        openNearby(app)
        XCTAssertTrue(element(app, "list-state-error").waitForExistence(timeout: wait))
        XCTAssertTrue(app.buttons["list-retry"].exists)
    }

    @MainActor
    func testListEmptyVenuesOffersBrowseNYC() {
        let app = launch("emptyVenues")
        openNearby(app)
        XCTAssertTrue(element(app, "list-state-empty").waitForExistence(timeout: wait))
        XCTAssertTrue(app.buttons["list-browse-nyc"].exists)
    }

    @MainActor
    func testListLocationDeniedBannerKeepsProvenanceVisible() {
        let app = launch("fixtureOK", extra: ["-UITestLocationDenied"])
        openNearby(app)
        XCTAssertTrue(element(app, "location-denied-banner").waitForExistence(timeout: wait))
        XCTAssertTrue(app.staticTexts["Fixture Roasters"].waitForExistence(timeout: wait))
        // 4.3(b): the differentiator (provenance) is still on screen.
        XCTAssertTrue(element(app, "provenance-stamp").firstMatch.exists)
    }

    @MainActor
    func testListEngineDownInSpanish() {
        let app = launch("engineDown", extra: ["-AppleLanguages", "(es)", "-AppleLocale", "es_US"])
        XCTAssertTrue(app.tabBars.buttons["Cercanos"].waitForExistence(timeout: wait))
        app.tabBars.buttons["Cercanos"].tap()
        XCTAssertTrue(element(app, "list-state-error").waitForExistence(timeout: wait))
        XCTAssertTrue(app.buttons["Reintentar"].exists)
    }

    // MARK: - Detail (photos)

    @MainActor
    func testDetailPhotosFailShowsCompactRetryAndKeepsClaims() {
        let app = launch("photosFail")
        openFixtureRoastersDetail(app)
        XCTAssertTrue(element(app, "photo-strip-error").waitForExistence(timeout: wait))
        XCTAssertTrue(app.buttons["photos-retry"].exists)
        XCTAssertTrue(app.staticTexts["Workability"].exists)
        XCTAssertFalse(element(app, "venue-photo-strip").exists)
    }

    @MainActor
    func testDetailPhotosEmptyCollapsesStripWithoutError() {
        let app = launch("photosEmpty")
        openFixtureRoastersDetail(app)
        XCTAssertTrue(app.staticTexts["Workability"].waitForExistence(timeout: wait))
        XCTAssertFalse(element(app, "venue-photo-strip").exists)
        XCTAssertFalse(element(app, "photo-strip-error").exists)
    }

    @MainActor
    func testDetailUnloadableThumbnailAndViewerOfferRetry() {
        let app = launch("fixtureOK")
        openFixtureRoastersDetail(app)
        XCTAssertTrue(element(app, "venue-photo-strip").waitForExistence(timeout: wait))
        let thumb = app.buttons["photo-thumb-failed"].firstMatch
        XCTAssertTrue(thumb.waitForExistence(timeout: wait))

        thumb.tap()
        XCTAssertTrue(element(app, "photo-viewer-error").waitForExistence(timeout: wait))
        XCTAssertTrue(app.buttons["photo-viewer-retry"].exists)
        XCTAssertTrue(element(app, "photo-attribution").exists)
        XCTAssertTrue(app.buttons["Close"].exists)
    }

    // MARK: - Saved

    @MainActor
    func testSavedEngineDownShowsRetry() {
        let app = launch("engineDown", savedIDs: "(\"fixture-roasters\")")
        openSaved(app)
        XCTAssertTrue(element(app, "saved-state-error").waitForExistence(timeout: wait))
        XCTAssertTrue(app.buttons["saved-retry"].exists)
    }

    @MainActor
    func testSavedPartialFailureShowsWhatLoadedPlusBanner() {
        let app = launch("fixtureOK", savedIDs: "(\"fixture-roasters\", \"missing-cafe\")")
        openSaved(app)
        XCTAssertTrue(app.staticTexts["Fixture Roasters"].waitForExistence(timeout: wait))
        XCTAssertTrue(element(app, "saved-partial-banner").exists)
        XCTAssertTrue(app.buttons["saved-partial-retry"].exists)
        XCTAssertTrue(element(app, "provenance-stamp").firstMatch.exists)
    }

    @MainActor
    func testSavedEmptyStateKeepsImportEntry() {
        let app = launch("fixtureOK")
        openSaved(app)
        XCTAssertTrue(element(app, "saved-state-empty").waitForExistence(timeout: wait))
        XCTAssertTrue(element(app, "import-saved-entry").exists)
    }

    // MARK: - Import

    @MainActor
    func testImportEngineDownIsNotReportedAsFileError() {
        let app = launch("engineDown")
        openSaved(app)
        XCTAssertTrue(element(app, "import-saved-entry").waitForExistence(timeout: wait))
        element(app, "import-saved-entry").tap()
        XCTAssertTrue(element(app, "import-state-engine-failed").waitForExistence(timeout: wait))
        XCTAssertTrue(app.buttons["import-retry"].exists)
        XCTAssertFalse(element(app, "import-state-file-failed").exists)
    }

    @MainActor
    func testImportFixtureFileMatchesAgainstHealthyEngine() {
        let app = launch("fixtureOK")
        openSaved(app)
        XCTAssertTrue(element(app, "import-saved-entry").waitForExistence(timeout: wait))
        element(app, "import-saved-entry").tap()
        XCTAssertTrue(app.staticTexts["Fixture Roasters"].waitForExistence(timeout: wait))
        XCTAssertFalse(element(app, "import-state-engine-failed").exists)
        XCTAssertFalse(element(app, "import-state-file-failed").exists)
    }

    // MARK: - Methodology

    @MainActor
    func testMethodologyReachableWhenEngineDown() {
        let app = launch("engineDown")
        openNearby(app)
        XCTAssertTrue(element(app, "list-state-error").waitForExistence(timeout: wait))
        let link = app.buttons["How scoring works"]
        XCTAssertTrue(link.waitForExistence(timeout: wait))
        link.tap()
        XCTAssertTrue(app.navigationBars["How Work Fit works"].waitForExistence(timeout: wait))
    }
}
