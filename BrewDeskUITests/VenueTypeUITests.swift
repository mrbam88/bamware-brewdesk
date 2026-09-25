import XCTest

/// brewdesk#240 — venue type badges + the "Place type" filter feature.
/// Bilal's decision on the ticket: "badge/tag WeWork and honestly any
/// non-cafés like parks... this could be a great new feature" — every
/// venue stays in the list; type becomes a visible, filterable dimension
/// instead of a reason to hide anything.
///
/// Fixture-driven (`-UITestScenario venueTypes`): one venue of each type
/// (cafe/library/park/coworking) plus one unrated café carrying
/// `scoreCoverage` — see `ScenarioVenueService.venueTypesVenues`.
///
/// New file (not `FilterUITests.swift`, owned by the concurrent brewdesk#77/
/// #222 lineage) — reuses `spotsTab`/`mapPin(named:)` from
/// `UITestHelpers.swift` read-only, same convention `UnobservedScoreUITests`
/// documents for itself.
final class VenueTypeUITests: XCTestCase {
    private let wait: TimeInterval = 15

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchVenueTypes() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipGates", "-UITestScenario", "venueTypes"]
        app.launch()
        XCTAssertTrue(app.spotsTab.waitForExistence(timeout: wait))
        app.spotsTab.tap()
        XCTAssertTrue(app.mapPin(named: "Fixture Types Cafe").waitForExistence(timeout: wait))
        return app
    }

    @MainActor
    private func openFilterMenuIfNeeded(_ app: XCUIApplication) {
        guard !app.descendants(matching: .any)["work-fit-filter-menu"].exists else { return }
        let button = app.buttons["filter-button"]
        XCTAssertTrue(button.waitForExistence(timeout: wait), "filter button missing")
        button.tap()
    }

    @MainActor
    private func shelf(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["map-discovery-shelf"].firstMatch
    }

    /// Same drag mechanics as `UnobservedScoreUITests.dragShelfToFullDetent`
    /// (duplicated locally rather than cross-file coupling, that file's own
    /// documented convention): the shelf's default `.medium` detent is a
    /// horizontal `LazyHStack` rail that only materializes ~3-4 cards of
    /// this fixture's five, and an UNRATED venue renders on the real map as
    /// a native `.speck` overlay — not a SwiftUI `Annotation`/button, so it
    /// carries no accessibility element at all there (`MapAnnotationPlanner`
    /// — `isRated` gates `.teardrop`/`.dot` vs. `.speck`). `.full`'s
    /// vertical list is the only reliable way to reach it.
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

    // MARK: - Badges visible (item 2 of the ticket)

    @MainActor
    func testBadgesVisibleOnEveryNonCafeTypeAndAbsentOnCafe() throws {
        let app = launchVenueTypes()
        // `.full`'s vertical shelf list, not `mapPin(named:)`: at five
        // tightly-clustered fixtures the real MapKit layer can collide/
        // demote a marker at the default camera zoom (`MapAnnotationPlanner`
        // — owned by the concurrent pin-rendering work, out of scope here),
        // and the horizontal rail only materializes ~3-4 cards. The shelf's
        // full list is what `UnobservedScoreUITests` already relies on for
        // the same reason — every row, deterministically.
        dragShelfToFullDetent(app)

        func row(_ name: String) -> XCUIElement {
            shelfButtons(app).matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
        }

        let library = row("Fixture Types Library")
        XCTAssertTrue(library.waitForExistence(timeout: wait), "library venue missing entirely")
        XCTAssertTrue(library.label.hasSuffix(", Library"), "library badge missing: \(library.label)")

        let park = row("Fixture Types Park")
        XCTAssertTrue(park.waitForExistence(timeout: wait), "park venue missing entirely")
        XCTAssertTrue(park.label.hasSuffix(", Park"), "park badge missing: \(park.label)")

        let coworking = row("Fixture Types Coworking")
        XCTAssertTrue(coworking.waitForExistence(timeout: wait), "coworking venue missing entirely")
        XCTAssertTrue(coworking.label.hasSuffix(", Coworking"), "coworking badge missing: \(coworking.label)")

        let cafe = row("Fixture Types Cafe")
        XCTAssertTrue(cafe.waitForExistence(timeout: wait))
        XCTAssertFalse(
            cafe.label.hasSuffix(", Library") || cafe.label.hasSuffix(", Park") || cafe.label.hasSuffix(", Coworking"),
            "a café must never carry a type badge: \(cafe.label)"
        )

        capture("venue-type-badges-shelf")
    }

    /// The badge's OWN accessibility identifier/label ("Library"), reachable
    /// on the detail header where `VenueTypeBadgeView` isn't folded into a
    /// combined parent label (unlike the shelf card/list row).
    @MainActor
    func testDetailHeaderShowsTheOwnTypeBadgeLabel() throws {
        let app = launchVenueTypes()

        app.mapPin(named: "Fixture Types Library").tap()
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: wait))

        let badge = app.descendants(matching: .any)["venue-type-badge-library"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: wait), "Library badge missing from the detail header")
        XCTAssertEqual(badge.label, "Library")

        capture("venue-type-badge-detail-library")
    }

    /// "Not rated yet" gets a reason (item 5): the unrated café fixture
    /// carries `scoreCoverage: {known:1, of:5}` — the detail explanation
    /// must say so, and keep the "Been here? Rate it." nudge.
    @MainActor
    func testUnratedVenueDetailShowsCoverageReason() throws {
        let app = launchVenueTypes()
        // Unrated venues draw as a native `.speck` map overlay, not a
        // SwiftUI button — only reachable through the shelf's `.full`
        // vertical list (see `dragShelfToFullDetent`'s doc comment).
        dragShelfToFullDetent(app)

        let unrated = shelfButtons(app).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Fixture Types Unrated Cafe,")
        ).firstMatch
        XCTAssertTrue(unrated.waitForExistence(timeout: wait), "unrated fixture venue missing from the shelf")
        unrated.tap()
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: wait))

        let explanation = app.descendants(matching: .any)["unobserved-explanation"]
        XCTAssertTrue(explanation.waitForExistence(timeout: wait), "Missing the unobserved explanation")
        XCTAssertTrue(explanation.label.contains("Based on 1 of 5 details"),
                      "coverage reason missing, got: \(explanation.label)")
        XCTAssertTrue(explanation.label.contains("Been here? Rate it."),
                      "the nudge must survive the new coverage copy, got: \(explanation.label)")

        capture("venue-detail-coverage-reason")
    }

    // MARK: - "Place type" filter as a feature (item 3)

    @MainActor
    func testPlaceTypeFilterNarrowsToParksAndUpdatesTheHeader() throws {
        let app = launchVenueTypes()

        let countLine = app.descendants(matching: .any)["map-count-line"].firstMatch
        XCTAssertTrue(countLine.waitForExistence(timeout: wait))
        // No filter yet: every fixture venue counts toward the plain
        // "N rated · M cafés" header — 5 total loaded.
        let initialCount = NSPredicate(format: "label CONTAINS %@", "5 cafés")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: initialCount, object: countLine)], timeout: wait),
            .completed,
            "header never settled on the unfiltered 5-venue count (was: \(countLine.label))"
        )

        openFilterMenuIfNeeded(app)
        let placeTypeRow = app.descendants(matching: .any)["filter-place-type-row"]
        XCTAssertTrue(placeTypeRow.waitForExistence(timeout: wait), "\"Place type\" row missing from the filter menu")

        // Every chip starts selected (all four on by default) — deselect
        // everything except Parks. The row is a horizontal scroller (four
        // chips, one of them "Coworking", don't fit a fixed 300pt popover
        // without wrapping — see `WorkFitFilterMenu.placeTypeRow`'s own doc
        // comment), so later chips need a swipe to become hittable first;
        // `waitUntilHittable` alone doesn't scroll a `ScrollView` into
        // position the way it does for a `List`.
        for type in ["cafe", "library", "coworking"] {
            let chip = app.buttons["filter-place-type-\(type)"].firstMatch
            XCTAssertTrue(chip.waitUntilHittable(timeout: wait), "\(type) chip never became hittable")
            XCTAssertTrue(chip.isSelected, "\(type) chip should start selected")
            chip.tap()
        }
        let parkChip = app.buttons["filter-place-type-park"].firstMatch
        XCTAssertTrue(parkChip.waitForExistence(timeout: wait))
        XCTAssertTrue(parkChip.isSelected, "park chip should stay selected — it was never tapped")

        // Only the park venue remains on screen.
        XCTAssertTrue(app.mapPin(named: "Fixture Types Park").waitForExistence(timeout: wait),
                      "park venue should still be visible")
        XCTAssertTrue(app.mapPin(named: "Fixture Types Cafe").waitForNonExistence(timeout: wait),
                      "café should be filtered out once narrowed to Parks")
        XCTAssertTrue(app.mapPin(named: "Fixture Types Library").waitForNonExistence(timeout: wait),
                      "library should be filtered out once narrowed to Parks")
        XCTAssertTrue(app.mapPin(named: "Fixture Types Coworking").waitForNonExistence(timeout: wait),
                      "coworking should be filtered out once narrowed to Parks")
        // The unrated café (also `venueType: "cafe"`) draws as a native
        // `.speck` overlay, never a button — `VenueTypeFilterMatrixTests`
        // (package tests) already proves the model-level exclusion; the
        // header count assertion below is this UI test's proof it actually
        // narrowed.

        // Header updates: a type-only filter now counts as active
        // (brewdesk#240), switching to the honest "N match · M unknown"
        // split — one confirmed park, nothing unknown.
        let narrowedCount = NSPredicate(format: "label CONTAINS %@", "1 match")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: narrowedCount, object: countLine)], timeout: wait),
            .completed,
            "header never updated to the narrowed park-only count (was: \(countLine.label))"
        )

        // Filter badge count includes the "Place type" dimension.
        let filterButton = app.buttons["filter-button"]
        let activeValue = NSPredicate(format: "value == %@", "1 active")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: activeValue, object: filterButton)], timeout: wait),
            .completed,
            "filter badge never settled on \"1 active\" (was: \(String(describing: filterButton.value)))"
        )

        capture("venue-type-filter-narrowed-to-parks")

        // Toggling the park chip back off proves it's a real TOGGLE, not a
        // one-way pick — the chip returns to unselected and the list goes
        // honestly empty (every type deselected).
        parkChip.tap()
        XCTAssertFalse(parkChip.isSelected, "park chip should flip back to unselected on a second tap")
    }
}
