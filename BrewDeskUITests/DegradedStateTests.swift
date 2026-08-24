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

    // brewdesk#117: Explore + Nearby collapsed into one Spots tab; Saved
    // and You are the other two. Detail now opens from Spots' map/shelf (a
    // sheet), not a Nearby-list push.
    @MainActor
    private func openSaved(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["tab-saved"].waitForExistence(timeout: wait))
        app.tabBars.buttons["tab-saved"].tap()
    }

    @MainActor
    private func openYou(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["tab-you"].waitForExistence(timeout: wait))
        app.tabBars.buttons["tab-you"].tap()
    }

    @MainActor
    private func openFixtureRoastersDetail(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["tab-spots"].waitForExistence(timeout: wait))
        app.tabBars.buttons["tab-spots"].tap()
        let pin = app.mapPin(named: "Fixture Roasters")
        XCTAssertTrue(pin.waitForExistence(timeout: wait))
        pin.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: wait))
    }

    // MARK: - Dataset stat strip (brewdesk#34)

    /// The provenance line must render on both discovery tabs whenever the
    /// engine reports health. It never did before #34: the strip's own
    /// `.task` hung off a view that did not exist while health was nil.
    @MainActor
    func testStatStripRendersOnSpots() {
        let app = launch("fixtureOK")
        XCTAssertTrue(element(app, "dataset-stat-strip").waitForExistence(timeout: wait),
                      "Dataset stat strip missing from Spots")
    }

    // MARK: - Cold start (brewdesk#28)
    // `-UITestSeedSnapshot` loads the bundled snapshot into a scenario launch.

    /// Airplane-mode fresh install: real rows within 2 s, an honest banner,
    /// and a retry — never a spinner-forever first paint.
    @MainActor
    func testColdStartOfflineShowsSnapshotRowsWithRetryWithinTwoSeconds() {
        let app = launch("offline", extra: ["-UITestSeedSnapshot"])
        XCTAssertTrue(element(app, "snapshot-banner-offline").waitForExistence(timeout: 2),
                      "no offline snapshot banner within 2 s of launch")
        XCTAssertTrue(app.buttons["snapshot-retry"].exists)
        XCTAssertFalse(element(app, "map-state-error").exists, "full-screen error shown over snapshot rows")
        XCTAssertFalse(element(app, "map-state-loading").exists)
        XCTAssertTrue(app.mapPins.firstMatch.waitForExistence(timeout: wait), "Spots shows no snapshot rows")
    }

    /// Slow network: snapshot rows first, a quiet "updating" banner, then the
    /// engine's answer replaces them and the banner goes away.
    @MainActor
    func testColdStartSlowNetworkShowsSnapshotThenLiveData() {
        let app = launch("slow", extra: ["-UITestSeedSnapshot"])
        XCTAssertTrue(element(app, "snapshot-banner-loading").waitForExistence(timeout: 2))
        XCTAssertFalse(element(app, "map-state-loading").exists, "spinner shown over snapshot rows")
        XCTAssertTrue(app.staticTexts["3 work spots"].waitForExistence(timeout: 20),
                      "live fixtures never replaced the snapshot")
        XCTAssertFalse(element(app, "snapshot-banner-loading").exists)
    }

    /// Reconnect recovers without relaunch: the first fetch fails offline,
    /// Retry on the banner brings live data into the same session.
    @MainActor
    func testColdStartRetryRecoversWithoutRelaunch() {
        let app = launch("offlineThenRecovers", extra: ["-UITestSeedSnapshot"])
        XCTAssertTrue(element(app, "snapshot-banner-offline").waitForExistence(timeout: wait))
        app.buttons["snapshot-retry"].tap()
        XCTAssertTrue(app.staticTexts["3 work spots"].waitForExistence(timeout: wait),
                      "retry did not bring live data")
        XCTAssertFalse(element(app, "snapshot-banner-offline").exists)
        XCTAssertFalse(element(app, "snapshot-banner-loading").exists)
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
        XCTAssertTrue(app.staticTexts["3 work spots"].waitForExistence(timeout: 20))
        XCTAssertFalse(element(app, "map-state-loading").exists)
    }

    // MARK: - Coverage (ve#46, bd#108)

    /// A viewport the engine only has OSM tier-0 data for: the honest
    /// baseline banner, never the removed "outside NYC" fallback text.
    @MainActor
    func testMapBaselineCityShowsBaselineBannerAndVenues() {
        let app = launch("baselineCity")
        XCTAssertTrue(element(app, "coverage-banner").waitForExistence(timeout: wait))
        XCTAssertTrue(app.staticTexts["Baseline data here — not yet researched. NYC is fully researched."].exists)
        XCTAssertFalse(element(app, "map-state-empty").exists)
        XCTAssertFalse(element(app, "map-state-error").exists)
    }

    /// A viewport the engine has nothing for at all: the existing empty
    /// state, no baseline banner.
    @MainActor
    func testMapNoCoverageShowsEmptyStateWithoutBanner() {
        let app = launch("noCoverage")
        XCTAssertTrue(element(app, "map-state-empty").waitForExistence(timeout: wait))
        XCTAssertTrue(app.buttons["map-browse-nyc"].exists)
        XCTAssertFalse(element(app, "coverage-banner").exists)
    }

    @MainActor
    func testMapLocationDeniedShowsBannerAndContent() {
        let app = launch("fixtureOK", extra: ["-UITestLocationDenied"])
        XCTAssertTrue(element(app, "location-denied-banner").waitForExistence(timeout: wait))
        XCTAssertTrue(app.buttons["location-open-settings"].exists)
        // Content still renders: denied location is a banner, not a wall.
        XCTAssertTrue(app.staticTexts["3 work spots"].waitForExistence(timeout: wait))
    }

    // MARK: - List (brewdesk#117: Nearby's list surface is gone — most of
    // this coverage is now identical to "MARK: - Map" above via the Spots
    // tab's `map-state-*` identifiers, so the exact-duplicate tests were
    // removed rather than ported. What's kept below is what the list
    // surface tested that Map didn't: provenance staying visible with
    // location denied, and a Spanish-locale error state.)

    @MainActor
    func testSpotsLocationDeniedBannerKeepsProvenanceVisible() {
        let app = launch("fixtureOK", extra: ["-UITestLocationDenied"])
        XCTAssertTrue(element(app, "location-denied-banner").waitForExistence(timeout: wait))
        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").waitForExistence(timeout: wait))
        // 4.3(b): the differentiator (provenance) is still on screen.
        XCTAssertTrue(element(app, "provenance-stamp").firstMatch.exists)
    }

    @MainActor
    func testMapEngineDownInSpanish() {
        let app = launch("engineDown", extra: ["-AppleLanguages", "(es)", "-AppleLocale", "es_US"])
        XCTAssertTrue(element(app, "map-state-error").waitForExistence(timeout: wait))
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

    // brewdesk#117: the list toolbar's "How scoring works" entry is gone
    // with Nearby; Methodology is reachable from the You tab regardless of
    // engine health (it doesn't depend on venue data), which is the
    // meaningful part of this test — Spots itself still shows its own
    // honest error state under the same engine-down condition.
    @MainActor
    func testMethodologyReachableWhenEngineDown() {
        let app = launch("engineDown")
        XCTAssertTrue(element(app, "map-state-error").waitForExistence(timeout: wait))

        openYou(app)
        let link = element(app, "methodology-link")
        XCTAssertTrue(link.waitForExistence(timeout: wait))
        link.tap()
        XCTAssertTrue(app.navigationBars["How Work Fit works"].waitForExistence(timeout: wait))
    }
}
