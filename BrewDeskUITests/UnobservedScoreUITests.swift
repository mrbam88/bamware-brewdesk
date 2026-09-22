import XCTest

/// bd#159, brewdesk#213 — a venue with no real evidence behind its score
/// must never show the engine's flat neutral fallback number as if it were
/// measured. All fixture-driven (`-UITestScenario fixtureOK`), which now
/// carries one unrated venue ("Fixture Unchecked Spot", all-estimate
/// claims) alongside the three original rated fixtures — see
/// `ScenarioVenueService.fixtureVenues`.
///
/// brewdesk#213: "Fixture Unchecked Spot" carries an EXPLICIT
/// `scoreDisplay: .notRated` (`ScenarioVenueService.unobservedFixtureVenue`)
/// — the modern server contract (a real JSON `null`), not just the older
/// `isObserved` heuristic on its own — so this file doubles as the ticket's
/// required "scenario fixture containing a `scoreDisplay: null` venue" UI
/// coverage: no digit anywhere in its shelf tile or its detail badge.
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
    /// viewport, so the fourth (always the unrated one, sorted last)
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
    func testUnobservedVenueShelfCardShowsNotRatedYetNeverTheNumber() throws {
        let app = launchFixtures()
        dragShelfToFullDetent(app)

        let unchecked = shelfButtons(app).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Fixture Unchecked Spot,")
        ).firstMatch
        XCTAssertTrue(unchecked.waitForExistence(timeout: wait), "Unrated fixture venue missing from the shelf")
        XCTAssertTrue(unchecked.label.contains("not rated yet"),
                      "VoiceOver label should read \"not rated yet\", got: \(unchecked.label)")
        XCTAssertFalse(unchecked.label.contains("Work Fit"),
                       "VoiceOver must never read the neutral fallback score, got: \(unchecked.label)")

        // brewdesk#213 acceptance criterion: no digit appears in the tile —
        // en dash + "NOT RATED" caption instead of a number. Scoped to just
        // the score tile's own explicit accessibility label (not the whole
        // card, which also carries a provenance date like "Updated July
        // 31" — a legitimate digit elsewhere on the same card).
        let tile = unchecked.descendants(matching: .any)["shelf-score-tile"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: wait), "Missing the shelf score tile")
        XCTAssertEqual(tile.label, "Not rated yet",
                       "Shelf tile should read \"Not rated yet\", got: \(tile.label)")
        XCTAssertNil(
            tile.label.rangeOfCharacter(from: .decimalDigits),
            "Shelf tile must show no digit for a null-scoreDisplay venue, got: \(tile.label)"
        )

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

        let unobservedIndex = try XCTUnwrap(labels.firstIndex { $0.contains("not rated yet") })
        XCTAssertEqual(unobservedIndex, labels.count - 1,
                       "Unrated venue must sort last; order was: \(labels)")
        for (index, label) in labels.enumerated() where index != unobservedIndex {
            XCTAssertTrue(label.contains("Work Fit"), "Expected a rated score at index \(index): \(label)")
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

        let badge = app.descendants(matching: .any)["score-badge"]
        XCTAssertTrue(badge.waitForExistence(timeout: wait), "Missing the detail score badge")
        XCTAssertTrue(app.staticTexts["Not rated yet"].firstMatch.waitForExistence(timeout: wait),
                      "Detail header should show the \"Not rated yet\" badge, not a number")
        // brewdesk#213 acceptance criterion: no digit in the detail badge
        // for a null-scoreDisplay venue.
        XCTAssertNil(badge.label.rangeOfCharacter(from: .decimalDigits),
                     "Detail badge must show no digit for a null-scoreDisplay venue, got: \(badge.label)")

        let explanation = app.descendants(matching: .any)["unobserved-explanation"]
        XCTAssertTrue(explanation.waitForExistence(timeout: wait), "Missing the one-line unobserved explanation")
        XCTAssertTrue(explanation.label.contains("haven't checked"),
                      "Explanation text missing, got: \(explanation.label)")
        // brewdesk#174 (C9) removed the store-submission surface gate this
        // used to reuse — the rate-it half of the line is unconditional now.
        XCTAssertTrue(explanation.label.contains("Rate it"),
                      "Should always offer the rate-it prompt, got: \(explanation.label)")
    }

    // MARK: - brewdesk#216: estimate/unknown value styling contrast

    /// "Fixture Unchecked Spot" is all-estimate claims (see file doc comment)
    /// — its Workability card is exactly the "everything is an estimate"
    /// case this ticket fixes (every value used to render `clayText`, a
    /// brick red that reads as "bad" and that Bilal, red-green colorblind,
    /// can't distinguish from the app's own "good" green). Runs the system
    /// contrast audit against the live detail sheet, scoped past the same
    /// two pre-existing low-contrast offenders `FilterUITests` already
    /// exempts (brewdesk#226) — neither is part of this ticket's card.
    @MainActor
    func testUnobservedVenueDetailWorkabilityCardPassesContrastAudit() throws {
        let app = launchFixtures()
        dragShelfToFullDetent(app)

        let unchecked = shelfButtons(app).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Fixture Unchecked Spot,")
        ).firstMatch
        XCTAssertTrue(unchecked.waitForExistence(timeout: wait))
        unchecked.tap()

        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: wait))
        let workabilityCard = app.descendants(matching: .any).matching(identifier: "workability-card").firstMatch
        XCTAssertTrue(workabilityCard.waitForExistence(timeout: wait), "Missing the Workability card")
        capture("detail-workability-unobserved-contrast")

        // Scoped to the Workability card's own frame, not the whole detail
        // screen: the screen carries several pre-existing low-contrast
        // elements with nothing to do with this ticket (the header's
        // neighborhood line, "ENV: Localhost", the map's "Numbers are Work
        // Fit" caption — the same class of offender `FilterUITests` already
        // exempts by label, brewdesk#226) and `BrewDeskUITests
        // .testVenueDetailAccessibilityAudit` is a documented pre-existing
        // failure on this exact screen for that reason. A frame-based scope
        // is more robust than another label list: it only ever asserts on
        // the card this ticket actually changed.
        let cardFrame = workabilityCard.frame
        try app.performAccessibilityAudit(for: .contrast) { issue in
            guard let frame = issue.element?.frame else { return true }
            return !frame.intersects(cardFrame)
        }
    }
}
