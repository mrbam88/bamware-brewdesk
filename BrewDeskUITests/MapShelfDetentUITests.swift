import XCTest

/// The map's bottom card is an honest sheet (brewdesk#76): the grabber the
/// card always showed now actually drags it through peek / medium / full
/// detents, and the card reopens at the detent the user left it for the rest
/// of the session. Fixture-driven (`-UITestScenario fixtureOK`), so these run
/// the same in Debug and Release, online or offline.
final class MapShelfDetentUITests: XCTestCase {
    private let wait: TimeInterval = 15

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launchFixtures() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-UITestScenario", "fixtureOK",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func shelf(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["map-discovery-shelf"].firstMatch
    }

    @MainActor
    private func grabber(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["map-shelf-grabber"].firstMatch
    }

    /// Drags the grabber to a normalized window y, then waits for the card's
    /// snap animation to settle.
    ///
    /// The press targets the top 12pt of the SHELF, where the grabber pill
    /// actually is. The grabber element's reported accessibility frame spans
    /// the whole card, so its center lands inside the full-detent list —
    /// where the ScrollView claims the drag and no detent changes (found
    /// while fixing brewdesk#125; a real finger on the pill never hits this).
    @MainActor
    private func dragGrabber(_ app: XCUIApplication, toNormalizedY y: CGFloat) {
        let handle = grabber(app)
        XCTAssertTrue(handle.waitForExistence(timeout: wait), "shelf grabber missing")
        let card = shelf(app)
        let window = app.windows.firstMatch
        card.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: card.frame.width / 2, dy: 12))
            .press(
                forDuration: 0.05,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y)),
                withVelocity: .default,
                thenHoldForDuration: 0.2
            )
        _ = settledShelfTop(app)
    }

    /// PR evidence: screenshots of the shelf at each detent, mirroring
    /// `ReviewerSimulationTests.capture`.
    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The card's top edge once its frame stops moving (snap animation done).
    @MainActor
    @discardableResult
    private func settledShelfTop(_ app: XCUIApplication) -> CGFloat {
        var last = shelf(app).frame.minY
        for _ in 0..<24 {
            Thread.sleep(forTimeInterval: 0.15)
            let now = shelf(app).frame.minY
            if abs(now - last) < 1 { return now }
            last = now
        }
        return last
    }

    // MARK: - Tests

    /// Fresh launch: the classic medium shelf — chips and the venue rail —
    /// with the grabber present.
    @MainActor
    func testShelfDefaultsToMediumWithVenueRail() throws {
        let app = launchFixtures()
        XCTAssertTrue(shelf(app).waitForExistence(timeout: wait), "discovery shelf missing")
        XCTAssertTrue(grabber(app).waitForExistence(timeout: wait), "shelf grabber missing")
        XCTAssertTrue(
            app.mapPins.firstMatch.waitForExistence(timeout: wait),
            "venue rail missing from the default shelf"
        )

        let height = app.windows.firstMatch.frame.height
        let top = settledShelfTop(app)
        XCTAssertGreaterThan(top, height * 0.50, "default shelf covers more than medium")
        XCTAssertLessThan(top, height * 0.78, "default shelf is not at medium (peek-sized?)")
        capture("shelf-medium-default")
    }

    /// Dragging the grabber down collapses the card to peek: filter chips stay
    /// usable, the venue rail gets out of the map's way.
    @MainActor
    func testGrabberDragsDownToPeek() throws {
        let app = launchFixtures()
        XCTAssertTrue(shelf(app).waitForExistence(timeout: wait))
        let height = app.windows.firstMatch.frame.height
        let mediumTop = settledShelfTop(app)

        dragGrabber(app, toNormalizedY: 0.98)

        let peekTop = settledShelfTop(app)
        XCTAssertGreaterThan(peekTop, height * 0.78, "shelf did not collapse to peek")
        XCTAssertGreaterThan(peekTop, mediumTop + 40, "drag down did not shrink the shelf")
        // UI3 (#118) moved the filter chips into WorkFitFilterMenu; peek is
        // the grabber-only sliver now, and the grabber must stay usable to
        // drag back out (#125).
        XCTAssertTrue(
            grabber(app).isHittable,
            "grabber must stay usable at peek"
        )
        capture("shelf-peek")
    }

    /// Dragging the grabber up expands the card to full, where the rail
    /// becomes a vertical list and a venue still opens its detail sheet.
    @MainActor
    func testGrabberDragsUpToFullAndListOpensDetail() throws {
        let app = launchFixtures()
        XCTAssertTrue(shelf(app).waitForExistence(timeout: wait))
        let height = app.windows.firstMatch.frame.height

        dragGrabber(app, toNormalizedY: 0.10)

        let fullTop = settledShelfTop(app)
        XCTAssertLessThan(fullTop, height * 0.45, "shelf did not expand to full")
        capture("shelf-full")

        let venue = app.mapPins.firstMatch
        XCTAssertTrue(venue.waitForExistence(timeout: wait), "full list shows no venues")
        venue.tap()
        XCTAssertTrue(
            app.staticTexts["Workability"].waitForExistence(timeout: wait),
            "tapping a venue in the full list no longer opens the detail sheet"
        )
    }

    /// The session remembers the last detent: collapse to peek, leave the
    /// tab, come back — still peek.
    @MainActor
    func testDetentIsRememberedAcrossTabRoundTrip() throws {
        let app = launchFixtures()
        XCTAssertTrue(shelf(app).waitForExistence(timeout: wait))
        let height = app.windows.firstMatch.frame.height

        dragGrabber(app, toNormalizedY: 0.98)
        XCTAssertGreaterThan(settledShelfTop(app), height * 0.78, "shelf did not collapse to peek")

        // brewdesk#117: Nearby is gone — Saved is the round trip now.
        XCTAssertTrue(app.tabBars.buttons["tab-saved"].waitForExistence(timeout: wait))
        app.tabBars.buttons["tab-saved"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: wait))
        app.tabBars.buttons["tab-spots"].tap()

        XCTAssertTrue(shelf(app).waitForExistence(timeout: wait), "shelf missing after tab round trip")
        XCTAssertGreaterThan(
            settledShelfTop(app), height * 0.78,
            "shelf forgot its peek detent after a tab round trip"
        )
    }

    /// The tab bar survives every detent — the reason the shelf is an in-tab
    /// card and not a modal sheet.
    @MainActor
    func testTabBarStaysReachableAtEveryDetent() throws {
        let app = launchFixtures()
        XCTAssertTrue(shelf(app).waitForExistence(timeout: wait))

        for y: CGFloat in [0.98, 0.10, 0.65] {
            dragGrabber(app, toNormalizedY: y)
            XCTAssertTrue(
                app.tabBars.buttons["tab-saved"].isHittable,
                "tab bar unreachable after dragging shelf toward y=\(y)"
            )
        }
    }
}
