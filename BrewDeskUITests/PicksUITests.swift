import XCTest

/// Bamware Picks on the Saved tab (bamware-ai#301), against the fixture
/// service: `onePick` is the state the list ships in, `tenPicks` a full
/// list, and every older scenario stands in for an engine with no picks.
final class PicksUITests: XCTestCase {
    private let wait: TimeInterval = 10

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ scenario: String, savedIDs: String = "()") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", scenario,
            "-brewdesk.saved-venue-ids", savedIDs,
        ]
        app.launch()
        XCTAssertTrue(app.savedTab.waitForExistence(timeout: wait))
        app.savedTab.tap()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    func testOnePickFillsTheEmptySavedTabAndOpensDetail() {
        let app = launch("onePick")
        XCTAssertTrue(app.staticTexts["Bamware Picks"].waitForExistence(timeout: wait))
        XCTAssertTrue(app.staticTexts["Hand-picked by us. Never paid for."].exists)
        XCTAssertTrue(app.staticTexts["Updated Nov 24"].exists)
        let row = element(app, "pick-row-1")
        XCTAssertTrue(row.exists)
        // Rank, name, neighbourhood, Work Fit, the line and the visit date.
        for part in ["Bamware Pick number 1", "Fixture Roasters", "Union Square", "Work Fit 84", "Fixture line.", "Visited Oct 27"] {
            XCTAssertTrue(row.label.contains(part), "row label is missing \"\(part)\": \(row.label)")
        }
        XCTAssertFalse(element(app, "pick-row-2").exists)

        // Nothing saved yet: the prompt and its way out are still there,
        // under Picks, with the corrected "from Spots" wording.
        XCTAssertTrue(element(app, "saved-state-empty").exists)
        XCTAssertTrue(app.staticTexts["Bookmark a spot from Spots to keep it here."].exists)
        XCTAssertTrue(app.buttons["saved-browse-spots"].exists)

        row.tap()
        XCTAssertTrue(element(app, "venue-detail-heading").waitForExistence(timeout: wait))
        XCTAssertEqual(element(app, "venue-detail-heading").label, "Fixture Roasters")
        XCTAssertTrue(element(app, "venue-detail-pick-blurb").exists)
        XCTAssertTrue(element(app, "pick-badge").exists)
        XCTAssertEqual(element(app, "pick-badge").label, "Bamware Pick number 1")
    }

    @MainActor
    func testSavingAPickFromItsRowAddsItToSavedSpots() {
        let app = launch("onePick")
        let save = app.buttons["pick-save-1"]
        XCTAssertTrue(save.waitForExistence(timeout: wait))
        XCTAssertEqual(save.value as? String, "Not saved")

        save.tap()

        // The bookmark saves in place: no navigation, Picks stays put, and
        // the café appears under "Your saved spots".
        XCTAssertTrue(app.staticTexts["Bamware Picks"].exists)
        XCTAssertFalse(element(app, "venue-detail-heading").exists)
        XCTAssertTrue(element(app, "provenance-stamp").firstMatch.waitForExistence(timeout: wait))
        XCTAssertFalse(element(app, "saved-state-empty").exists)
        XCTAssertEqual(app.buttons["pick-save-1"].value as? String, "Saved")
    }

    @MainActor
    func testTenPicksAreRankedAndTheLastIsReachable() {
        let app = launch("tenPicks", savedIDs: "(\"fixture-pick-4\")")
        XCTAssertTrue(app.staticTexts["Fixture Pick One Roasters"].waitForExistence(timeout: wait))
        XCTAssertTrue(element(app, "pick-row-1").label.contains("Bamware Pick number 1"))
        XCTAssertEqual(app.buttons["pick-save-1"].value as? String, "Not saved")

        // The list is lazy: rows exist once scrolled to.
        let fourth = app.buttons["pick-save-4"]
        let last = element(app, "pick-row-10")
        var sawFourthSaved = false
        for _ in 0..<14 where !last.exists {
            if fourth.exists, fourth.value as? String == "Saved" { sawFourthSaved = true }
            app.swipeUp()
        }
        XCTAssertTrue(sawFourthSaved, "pick 4 is saved, so its bookmark is filled")
        XCTAssertTrue(last.exists, "the tenth pick is in the list")
        XCTAssertTrue(last.label.contains("Visited Dec 14, 2025"), "a visit from an earlier year names the year: \(last.label)")
    }

    @MainActor
    func testNoPicksLeavesTheSavedTabAsItWas() {
        // `fixtureOK` serves an empty list, like an engine with none.
        let app = launch("fixtureOK")
        XCTAssertTrue(element(app, "saved-state-empty").waitForExistence(timeout: wait))
        XCTAssertFalse(app.staticTexts["Bamware Picks"].exists)
        XCTAssertFalse(element(app, "saved-spots-subheader").exists)
    }

    @MainActor
    func testAFailingEngineShowsNoPicksAndNoPicksError() {
        // Saved spots keep their own error state; Picks adds none.
        let app = launch("engineDown")
        XCTAssertTrue(element(app, "saved-state-empty").waitForExistence(timeout: wait))
        XCTAssertFalse(app.staticTexts["Bamware Picks"].exists)
        XCTAssertFalse(element(app, "pick-detail-error").exists)
    }
}
