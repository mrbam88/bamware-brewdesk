import XCTest

/// bd#223 — "in the search field, it should remember the recent search
/// history." `RecentSearchStore`'s own logic (capacity, de-duplication,
/// word-prefix matching) is unit-tested directly (`RecentSearchStoreTests`,
/// package tests); this proves the UI wiring end to end: a real selection or
/// a submitted query records a "Recent" row, tapping a recent café replays
/// PR #220's exact fly-to, and swipe-delete/Clear both work.
final class SearchRecentsUITests: XCTestCase {
    private let wait: TimeInterval = 15

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchSpots() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipGates", "-UITestScenario", "fixtureOK"]
        app.launch()
        XCTAssertTrue(app.spotsTab.waitForExistence(timeout: wait))
        app.spotsTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["map-header-card"].waitForExistence(timeout: wait))
        return app
    }

    @MainActor
    private func searchField(_ app: XCUIApplication) -> XCUIElement {
        let field = app.textFields["Search spots"]
        XCTAssertTrue(field.waitForExistence(timeout: wait), "Spots search field missing")
        return field
    }

    private static func waitFor(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return condition()
    }

    /// Selecting a search result records a "Recent" café row (leading
    /// `mappin.and.ellipse`, per the ticket) — reopening search shows it,
    /// and tapping it replays PR #220's exact selection behavior (walking-
    /// scale fly-to, `.medium` sheet, committed field label) FROM THE
    /// STORED ENTRY, with no re-typed search.
    @MainActor
    func testSelectingACafeRecordsARecentAndTappingItFliesBackToIt() throws {
        let app = launchSpots()

        let field = searchField(app)
        field.tap()
        field.typeText("Roasters")
        let shelf = app.descendants(matching: .any)["map-discovery-shelf"]
        XCTAssertTrue(shelf.waitForExistence(timeout: wait))
        let row = shelf.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture Roasters,")).firstMatch
        XCTAssertTrue(row.waitUntilHittable(timeout: wait), "search result row never became hittable")
        row.tap()

        let committedLabel = app.descendants(matching: .any)["search-committed-label"]
        XCTAssertTrue(committedLabel.waitForExistence(timeout: wait), "selection never committed")

        let closeButton = app.buttons["detail-close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: wait))
        closeButton.tap()

        // Reopen search — the field still shows the committed label; tapping
        // IT starts a fresh, empty search (`searchHeader`'s own documented
        // behavior).
        let committedFieldLabel = app.descendants(matching: .any)["search-committed-label"]
        if committedFieldLabel.waitForExistence(timeout: 3) {
            committedFieldLabel.tap()
        } else {
            searchField(app).tap()
        }

        let recents = app.descendants(matching: .any)["search-recents"]
        XCTAssertTrue(recents.waitForExistence(timeout: wait), "Recent section never appeared after a selection")
        let recentRow = app.descendants(matching: .any)["search-recent-row-0"]
        XCTAssertTrue(recentRow.waitForExistence(timeout: wait), "recent café row missing")
        XCTAssertTrue(
            recentRow.label.contains("Fixture Roasters"),
            "recent row does not name the selected café: \(recentRow.label)"
        )

        recentRow.tap()

        // Same objective proof `SearchUITests
        // .testSelectingAFarAwaySearchResultFliesTheMapToIt` uses for a live
        // row tap — `map-selected-marker` + walking-scale `map-camera-mpp`.
        let selectedMarker = app.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "map-selected-marker", "Fixture Roasters,")
        ).firstMatch
        XCTAssertTrue(selectedMarker.waitForExistence(timeout: wait), "tapping the recent never re-selected the café")

        let mppElement = app.descendants(matching: .any)["map-camera-mpp"]
        XCTAssertTrue(
            Self.waitFor(timeout: wait) {
                (Double((mppElement.value as? String) ?? "") ?? .greatestFiniteMagnitude) <= 2.6
            },
            "tapping a recent café did not fly to walking scale"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["search-committed-label"].waitForExistence(timeout: wait),
            "tapping a recent café did not commit the field to its name"
        )
    }

    /// A submitted query that never resolves to exactly one result (no row
    /// picked) records a DIFFERENT recent kind — `clock.arrow.circlepath`,
    /// not `mappin.and.ellipse` — and tapping it puts the text back and
    /// re-runs the search rather than selecting anything.
    @MainActor
    func testSubmittingAQueryRecordsARecentAndTappingItReRunsTheSearch() throws {
        let app = launchSpots()

        let field = searchField(app)
        field.tap()
        // "Fixture" matches all three fixtures — never resolves to one, so
        // this never auto-selects (the field stays an editable TextField,
        // not a committed label).
        field.typeText("Fixture\n")
        Thread.sleep(forTimeInterval: 1.0)

        // The submitted text is still IN the field — clear it back to empty
        // so the shelf shows the "Recent" SECTION (not the inline
        // while-typing suggestions, which need non-empty text).
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Fixture".count))

        let recents = app.descendants(matching: .any)["search-recents"]
        XCTAssertTrue(recents.waitForExistence(timeout: wait), "Recent section never appeared after a submitted query")
        let recentRow = app.descendants(matching: .any)["search-recent-row-0"]
        XCTAssertTrue(recentRow.waitForExistence(timeout: wait))
        XCTAssertTrue(recentRow.label.contains("Fixture"), "recent query row missing its text: \(recentRow.label)")

        recentRow.tap()
        XCTAssertTrue(
            Self.waitFor(timeout: wait) { (searchField(app).value as? String) == "Fixture" },
            "tapping a recent query did not put its text back in the field"
        )
    }

    /// Swipe-to-delete on one row, then "Clear" on the section header. Uses
    /// two submitted QUERIES (never a café selection, which would commit the
    /// field to a static label) — "Fixture" (all three) and "zzznomatch"
    /// (none) — neither resolves to exactly one result, so neither
    /// auto-selects.
    @MainActor
    func testSwipeToDeleteRemovesARecentRowAndClearRemovesAll() throws {
        let app = launchSpots()

        let field = searchField(app)
        field.tap()
        field.typeText("Fixture\n")
        Thread.sleep(forTimeInterval: 1.0)

        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Fixture".count))
        field.typeText("zzznomatch\n")
        Thread.sleep(forTimeInterval: 1.0)

        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "zzznomatch".count))

        let recents = app.descendants(matching: .any)["search-recents"]
        XCTAssertTrue(recents.waitForExistence(timeout: wait), "Recent section never appeared")
        XCTAssertTrue(app.descendants(matching: .any)["search-recent-row-0"].waitForExistence(timeout: wait))
        XCTAssertTrue(app.descendants(matching: .any)["search-recent-row-1"].waitForExistence(timeout: wait))

        // A manual, coordinate-based drag rather than `.swipeLeft()` — the
        // latter's synthesized start/end points are derived from the
        // element's own reported accessibility frame, which briefly changes
        // shape as the row animates during the drag; an explicit horizontal
        // drag confined to a fixed screen rect avoids that.
        let rowToDelete = app.descendants(matching: .any)["search-recent-row-0"]
        let rowFrame = rowToDelete.frame
        let dragY = rowFrame.midY
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: rowFrame.maxX - 10, dy: dragY))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: rowFrame.minX + 4, dy: dragY))
            )
        XCTAssertTrue(
            Self.waitFor(timeout: wait) { !app.descendants(matching: .any)["search-recent-row-1"].exists },
            "swipe-to-delete did not remove a recent row"
        )

        // Defensive re-focus, cheap insurance against any timing flake in
        // the drag/keyboard settle above — the real bug this uncovered
        // (a swipe also firing the row's own tap action, since fixed with
        // `.highPriorityGesture` in `SwipeToDeleteRow`) is covered by the
        // assertion right above this.
        if !app.descendants(matching: .any)["search-recents-clear"].exists {
            searchField(app).tap()
        }
        let clearButton = app.descendants(matching: .any)["search-recents-clear"]
        XCTAssertTrue(
            clearButton.waitForExistence(timeout: wait),
            "Clear button missing. row0.exists=\(app.descendants(matching: .any)["search-recent-row-0"].exists) " +
            "recents.exists=\(app.descendants(matching: .any)["search-recents"].exists) " +
            "textField.exists=\(app.textFields["Search spots"].exists) " +
            "committedLabel.exists=\(app.descendants(matching: .any)["search-committed-label"].exists) " +
            "keyboards=\(app.keyboards.count)"
        )
        clearButton.tap()
        XCTAssertTrue(
            Self.waitFor(timeout: wait) { !app.descendants(matching: .any)["search-recent-row-0"].exists },
            "Clear did not remove the remaining recent"
        )
    }
}
