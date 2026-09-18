import XCTest

/// bd#159 — a venue with no real evidence behind its score must never show
/// the engine's flat neutral fallback number as if it were measured. All
/// fixture-driven (`-UITestScenario fixtureOK`), which now carries one
/// unobserved venue ("Fixture Unchecked Spot", all-estimate claims)
/// alongside the three original observed fixtures — see
/// `ScenarioVenueService.fixtureVenues`.
///
/// New file, not `SearchUITests.swift`/`UITestHelpers.swift` (owned by the
/// brewdesk#158 agent in parallel) — reuses `spotsTab`/`mapPin(named:)`
/// read-only.
final class UnobservedScoreUITests: XCTestCase {
    private let wait: TimeInterval = 15

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchFixtures() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipGates", "-UITestScenario", "fixtureOK"]
        app.launch()
        XCTAssertTrue(app.spotsTab.waitForExistence(timeout: wait))
        app.spotsTab.tap()
        return app
    }

    @MainActor
    private func shelf(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["map-discovery-shelf"].firstMatch
    }

    /// The shelf's default `.medium` detent is a horizontal `LazyHStack`
    /// rail — at four cards it only materializes ~3 within the initial
    /// viewport, so the fourth (always the unobserved one, sorted last)
    /// never enters the AX tree without a drag. `.full` switches
    /// `DiscoveryShelfCard` to a vertical list, where all four rows fit the
    /// screen at once and all render immediately. Same drag mechanics as
    /// `MapShelfDetentUITests.dragGrabber`, duplicated here rather than
    /// reusing that file (owned by the brewdesk#158 agent in parallel).
    @MainActor
    private func dragShelfToFullDetent(_ app: XCUIApplication) {
        let grabber = app.descendants(matching: .any)["map-shelf-grabber"].firstMatch
        XCTAssertTrue(grabber.waitForExistence(timeout: wait), "shelf grabber missing")
        let card = shelf(app)
        let window = app.windows.firstMatch
        card.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: card.frame.width / 2, dy: 12))
            .press(
                forDuration: 0.05,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10)),
                withVelocity: .default,
                thenHoldForDuration: 0.2
            )
        var last = shelf(app).frame.minY
        for _ in 0..<24 {
            Thread.sleep(forTimeInterval: 0.15)
            let now = shelf(app).frame.minY
            if abs(now - last) < 1 { break }
            last = now
        }
    }

    /// Only ever holds `DiscoveryShelfCard` venue buttons — scopes out
    /// MapKit's own pins (which CafeMapScreen, owned by brewdesk#158, still
    /// labels with the raw "Work Fit N" text pending that file's own
    /// update).
    @MainActor
    private func shelfButtons(_ app: XCUIApplication) -> XCUIElementQuery {
        shelf(app).buttons
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Shelf card

    @MainActor
    func testUnobservedVenueShelfCardShowsNotCheckedYetNeverTheNumber() throws {
        let app = launchFixtures()
        dragShelfToFullDetent(app)

        let unchecked = shelfButtons(app).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Fixture Unchecked Spot,")
        ).firstMatch
        XCTAssertTrue(unchecked.waitForExistence(timeout: wait), "Unobserved fixture venue missing from the shelf")
        XCTAssertTrue(unchecked.label.contains("not checked yet"),
                      "VoiceOver label should read \"not checked yet\", got: \(unchecked.label)")
        XCTAssertFalse(unchecked.label.contains("Work Fit"),
                       "VoiceOver must never read the neutral fallback score, got: \(unchecked.label)")
        XCTAssertTrue(app.staticTexts["Not checked yet"].firstMatch.exists,
                      "Shelf card should show the \"Not checked yet\" badge text, never a number")

        // An observed fixture still shows its real score, for contrast.
        let roasters = shelfButtons(app).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Fixture Roasters,")
        ).firstMatch
        XCTAssertTrue(roasters.waitForExistence(timeout: wait))
        XCTAssertTrue(roasters.label.contains("Work Fit 84"),
                      "Observed fixture should still show its real score, got: \(roasters.label)")

        capture("shelf-list-observed-and-unobserved")
    }

    // MARK: - Ordering (brewdesk#159 acceptance criterion)

    @MainActor
    func testObservedVenuesSortBeforeUnobservedInTheShelf() throws {
        let app = launchFixtures()
        dragShelfToFullDetent(app)

        let buttons = shelfButtons(app).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Fixture ")
        )
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: wait), "Shelf rendered no venue cards")

        let labels = (0..<buttons.count).map { buttons.element(boundBy: $0).label }
        XCTAssertEqual(labels.count, 4, "Expected all four fixtureOK venues on the shelf list")

        let unobservedIndex = try XCTUnwrap(labels.firstIndex { $0.contains("not checked yet") })
        XCTAssertEqual(unobservedIndex, labels.count - 1,
                       "Unobserved venue must sort last; order was: \(labels)")
        for (index, label) in labels.enumerated() where index != unobservedIndex {
            XCTAssertTrue(label.contains("Work Fit"), "Expected an observed score at index \(index): \(label)")
        }
    }

    // MARK: - Detail header

    @MainActor
    func testUnobservedVenueDetailShowsBadgeAndExplanation() throws {
        let app = launchFixtures()
        dragShelfToFullDetent(app)

        let unchecked = shelfButtons(app).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Fixture Unchecked Spot,")
        ).firstMatch
        XCTAssertTrue(unchecked.waitForExistence(timeout: wait))
        unchecked.tap()

        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: wait))
        capture("detail-header-unobserved")

        XCTAssertTrue(app.staticTexts["Not checked yet"].firstMatch.waitForExistence(timeout: wait),
                      "Detail header should show the \"Not checked yet\" badge, not a number")
        let explanation = app.descendants(matching: .any)["unobserved-explanation"]
        XCTAssertTrue(explanation.waitForExistence(timeout: wait), "Missing the one-line unobserved explanation")
        XCTAssertTrue(explanation.label.contains("haven't checked"),
                      "Explanation text missing, got: \(explanation.label)")
        // brewdesk#174 (C9) removed the store-submission surface gate this
        // used to reuse — the rate-it half of the line is unconditional now.
        XCTAssertTrue(explanation.label.contains("Rate it"),
                      "Should always offer the rate-it prompt, got: \(explanation.label)")
    }
}
