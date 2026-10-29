import XCTest

/// Ask tab (bamware-brewdesk#247), fixture-driven: the tab exists on a
/// scenario launch, a typed question round-trips to a reply with venue
/// cards, a card opens the existing venue detail, and an engine failure
/// renders the inline Retry row. `ScenarioChatClient` stands in for
/// `POST /v1/chat`, so this passes with no network and no engine.
final class AskTabUITests: XCTestCase {
    private let wait: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchAsk(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipGates", "-UITestScenario", scenario]
        app.launch()
        XCTAssertTrue(app.askTab.waitForExistence(timeout: wait), "Ask tab missing on a scenario launch")
        // brewdesk#131: right after a cold launch the floating tab bar's
        // buttons can exist with no computable hit point yet (the first
        // test of a run saw `{-1, -1}`), so wait for hittability and give
        // the tap one more try if the screen didn't switch.
        let emptyState = app.descendants(matching: .any)["ask-empty-state"]
        app.askTab.waitUntilHittable(timeout: wait)
        app.askTab.tap()
        if !emptyState.waitForExistence(timeout: 3) {
            app.askTab.tap()
        }
        XCTAssertTrue(emptyState.waitForExistence(timeout: wait), "Ask tab did not open")
        return app
    }

    @MainActor
    func testTypedQuestionGetsReplyAndCardOpensDetail() throws {
        let app = launchAsk(scenario: "fixtureOK")

        let input = app.textFields["ask-input"]
        XCTAssertTrue(input.waitForExistence(timeout: wait))
        let send = app.buttons["ask-send"]
        XCTAssertFalse(send.isEnabled, "Send must be disabled while the composer is empty")

        input.tap()
        input.typeText("quiet spot with outlets")
        XCTAssertTrue(send.isEnabled)
        send.tap()

        let reply = app.staticTexts["ask-reply"]
        XCTAssertTrue(reply.waitForExistence(timeout: wait), "assistant reply never appeared")
        XCTAssertTrue(reply.label.contains("Fixture Roasters"))
        XCTAssertTrue(app.staticTexts["ask-user-message"].exists)

        let card = app.buttons["ask-venue-card-fixture-roasters"]
        XCTAssertTrue(card.waitForExistence(timeout: wait), "Roasters card missing under the reply")
        XCTAssertTrue(app.buttons["ask-venue-card-fixture-library"].exists)
        XCTAssertTrue(card.waitUntilHittable(timeout: wait))
        card.tap()

        // The detail's nav title only appears once its header scrolls off
        // (`VenueDetailScreen.showNavTitle`), so key off the screen's own
        // identifier and the heading that carries the venue name.
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: wait),
                      "tapping the card did not push venue detail")
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-heading"].label.contains("Fixture Roasters"))
    }

    @MainActor
    func testSuggestionChipSendsWithoutTyping() throws {
        let app = launchAsk(scenario: "fixtureOK")

        let chip = app.buttons["ask-suggestion-0"]
        XCTAssertTrue(chip.waitForExistence(timeout: wait))
        chip.tap()

        XCTAssertTrue(app.staticTexts["ask-reply"].waitForExistence(timeout: wait))
        XCTAssertFalse(app.descendants(matching: .any)["ask-empty-state"].exists,
                       "empty state should give way to the transcript")
    }

    @MainActor
    func testEngineDownShowsRetryRow() throws {
        let app = launchAsk(scenario: "engineDown")

        let chip = app.buttons["ask-suggestion-1"]
        XCTAssertTrue(chip.waitForExistence(timeout: wait))
        chip.tap()

        XCTAssertTrue(app.staticTexts["ask-state-unreachable"].waitForExistence(timeout: wait),
                      "engine failure did not render the unreachable row")
        XCTAssertTrue(app.buttons["ask-retry"].exists, "Retry button missing")
        XCTAssertFalse(app.staticTexts["ask-reply"].exists)
    }
}
