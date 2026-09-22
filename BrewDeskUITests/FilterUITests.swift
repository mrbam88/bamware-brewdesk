import XCTest

/// brewdesk#77 — selecting every filter must never empty the list for the
/// wrong reason. Fixture-driven (`-UITestScenario fixtureOK`): Roasters is
/// cafe/fast/plenty/some-seating/laptop-unrestricted, Reading Room is a
/// library, Corner Cafe is laptop-discouraged.
///
/// brewdesk#118: retargeted from the old Nearby tab's `Menu`
/// (submenu-then-option taps) to the Spots tab's anchored
/// `WorkFitFilterMenu` (segmented option taps, no submenu step — the
/// popover stays open across picks since filters apply live). Taps only;
/// not iterated to green — a stabilization pass covers full pass/fail.
final class FilterUITests: XCTestCase {
    private let wait: TimeInterval = 10

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
        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").waitForExistence(timeout: wait))
        return app
    }

    /// `WorkFitFilterMenu` is a popover that stays open across picks
    /// (filters apply live) — opens it only if it isn't already showing,
    /// unlike the old `Menu` which closed after every selection.
    @MainActor
    private func openFilterMenuIfNeeded(_ app: XCUIApplication) {
        guard !app.descendants(matching: .any)["work-fit-filter-menu"].exists else { return }
        let button = app.buttons["filter-button"]
        XCTAssertTrue(button.waitForExistence(timeout: wait), "filter button missing")
        button.tap()
    }

    /// One segmented option inside a dimension row, e.g. `identifier:
    /// "filter-wifi-fast"` — no submenu step, unlike the old `Menu`'s
    /// labeled-submenu pickers.
    @MainActor
    private func pick(_ app: XCUIApplication, identifier: String) {
        openFilterMenuIfNeeded(app)
        let choice = app.buttons[identifier].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: wait), "\(identifier) option missing")
        choice.tap()
    }

    @MainActor
    private func toggleLaptopFriendly(_ app: XCUIApplication) {
        openFilterMenuIfNeeded(app)
        let toggle = app.switches["filter-laptop-friendly"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: wait))
        // A SwiftUI Toggle's accessibility element spans label + switch; a
        // centre tap lands on the label and does not flip it on iOS 26. Tap the
        // trailing edge where the switch lives, then prove it flipped.
        let before = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let flipped = NSPredicate(format: "value != %@", before ?? "")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: flipped, object: toggle)], timeout: wait),
                       .completed, "laptop-friendly toggle did not flip")
    }

    @MainActor
    func testSelectingEveryFilterStillShowsQualifyingCafes() throws {
        let app = launchSpots()

        toggleLaptopFriendly(app)
        pick(app, identifier: "filter-wifi-fast")
        pick(app, identifier: "filter-outlets-plenty")
        pick(app, identifier: "filter-seating-some")
        // brewdesk#118: WorkFitFilterMenu has no spot-type dimension (out of
        // scope per the mockups) — the old "Spot type: cafe" pick has no
        // retarget, so Reading Room's library type no longer filters out
        // here; left for the stabilization pass.

        // The qualifying cafe survives "everything selected" (the bug showed
        // zero cafes here); the laptop-hostile cafe drops out.
        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").waitForExistence(timeout: wait),
                      "All filters selected emptied the list (brewdesk#77 regression)")
        // Wait for the filter to apply: asserting `.exists == false` the instant
        // the last chip is tapped races the re-plan (brewdesk#166).
        XCTAssertTrue(app.mapPin(named: "Fixture Corner Cafe").waitForNonExistence(timeout: wait),
                      "Laptop-discouraged cafe should not pass laptop-friendly")
    }

    // MARK: - Honest filters (brewdesk#222)

    @MainActor
    private func launchFilterHonesty() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipGates", "-UITestScenario", "filterHonesty"]
        app.launch()
        XCTAssertTrue(app.spotsTab.waitForExistence(timeout: wait))
        app.spotsTab.tap()
        XCTAssertTrue(app.mapPin(named: "Fixture Confirmed Cafe").waitForExistence(timeout: wait))
        return app
    }

    /// Drags the shelf grabber to `.full` so the sectioned list (rather than
    /// the compact rail) renders — mirrors `MapShelfDetentUITests`'
    /// `dragGrabber`, duplicated locally rather than cross-file coupling for
    /// one call site.
    @MainActor
    private func openFullShelf(_ app: XCUIApplication) {
        let handle = app.descendants(matching: .any)["map-shelf-grabber"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: wait), "shelf grabber missing")
        let shelf = app.descendants(matching: .any)["map-discovery-shelf"].firstMatch
        let window = app.windows.firstMatch
        shelf.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: shelf.frame.width / 2, dy: 12))
            .press(
                forDuration: 0.05,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10)),
                withVelocity: .default,
                thenHoldForDuration: 0.2
            )
    }

    /// `-UITestScenario filterHonesty`: one CONFIRMED café (Wi-Fi fast), one
    /// filter-UNKNOWN café (Wi-Fi unknown — the WeWork TestFlight build 28
    /// report), one KNOWN-EXCLUDED café (Wi-Fi slow), against a "fast
    /// Wi-Fi" filter. Asserts the header count, both sections, the
    /// collapsed-by-default unknown toggle, and — the acceptance criterion
    /// verbatim — that the unknown café is never in the confirmed section.
    @MainActor
    func testFastWifiFilterSeparatesConfirmedFromUnknownAndHidesExcluded() throws {
        let app = launchFilterHonesty()

        pick(app, identifier: "filter-wifi-fast")

        // Header: "1 match · 1 unknown" — the excluded café never counts
        // toward either number.
        let countLine = app.descendants(matching: .any)["map-count-line"].firstMatch
        XCTAssertTrue(countLine.waitForExistence(timeout: wait))
        let settledCount = NSPredicate(format: "label CONTAINS %@", "1 match")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: settledCount, object: countLine)], timeout: wait),
            .completed,
            "header never settled on the honest match/unknown count (was: \(countLine.label))"
        )
        XCTAssertTrue(countLine.label.contains("1 unknown"), "header missing the unknown count: \(countLine.label)")

        // Map: the excluded café is hidden outright — not a pin, not a
        // speck, not anywhere in the accessibility tree as a venue.
        XCTAssertTrue(app.mapPin(named: "Fixture Slow WiFi Cafe").waitForNonExistence(timeout: wait),
                      "known-slow café must be excluded, not just demoted")
        // The unknown café never renders as a normal (numbered) pin —
        // demoted to a faint speck, which carries no "Work Fit" accessibility
        // label at all.
        XCTAssertFalse(app.mapPin(named: "Fixture Unknown WiFi Cafe").exists,
                        "filter-unknown café must not render as a confirmed pin")

        openFullShelf(app)

        let confirmedSection = app.descendants(matching: .any)["filter-confirmed-section"]
        XCTAssertTrue(confirmedSection.waitForExistence(timeout: wait), "confirmed section missing")
        XCTAssertTrue(
            confirmedSection.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture Confirmed Cafe,")).firstMatch
                .waitForExistence(timeout: wait),
            "confirmed café missing from the confirmed section"
        )
        XCTAssertFalse(
            confirmedSection.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture Unknown WiFi Cafe,")).firstMatch.exists,
            "the acceptance criterion: an unknown-Wi-Fi café must never appear in the confirmed section"
        )
        XCTAssertFalse(
            confirmedSection.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture Slow WiFi Cafe,")).firstMatch.exists,
            "excluded café leaked into the confirmed section"
        )

        // Unknown section: present, collapsed by default (the row isn't in
        // the tree yet), toggle identifier exists.
        let unknownToggle = app.descendants(matching: .any)["filter-unknown-toggle"]
        XCTAssertTrue(unknownToggle.waitForExistence(timeout: wait), "unknown section toggle missing")
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture Unknown WiFi Cafe,")).firstMatch.exists,
            "unknown section must start collapsed"
        )

        unknownToggle.tap()
        let unknownSection = app.descendants(matching: .any)["filter-unknown-section"]
        XCTAssertTrue(unknownSection.waitForExistence(timeout: wait), "unknown section missing after expanding")
        XCTAssertTrue(
            unknownSection.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture Unknown WiFi Cafe,")).firstMatch
                .waitForExistence(timeout: wait),
            "unknown café missing from the expanded unknown section"
        )
        XCTAssertFalse(
            unknownSection.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture Slow WiFi Cafe,")).firstMatch.exists,
            "excluded café leaked into the unknown section"
        )
    }

    /// `filterHonestyVenues`' confirmed café is known-SCARCE on outlets, so
    /// adding an outlets-plenty floor on top of "fast Wi-Fi" excludes it —
    /// the confirmed section goes honestly empty while the unknown café
    /// (known-plenty outlets, still unknown-Wi-Fi) stays in the unknown
    /// section: confirmed empty state + nudge, unknown section forced open.
    @MainActor
    func testEmptyConfirmedSectionShowsHonestEmptyStateAndNudge() throws {
        let app = launchFilterHonesty()

        pick(app, identifier: "filter-wifi-fast")
        pick(app, identifier: "filter-outlets-plenty")
        openFullShelf(app)

        let confirmedSection = app.descendants(matching: .any)["filter-confirmed-section"]
        XCTAssertTrue(confirmedSection.waitForExistence(timeout: wait), "confirmed section missing")
        XCTAssertTrue(
            confirmedSection.staticTexts["No café here is confirmed for these filters yet"].waitForExistence(timeout: wait),
            "honest empty-confirmed copy missing"
        )
        XCTAssertTrue(
            confirmedSection.staticTexts["Been here? Rate it."].waitForExistence(timeout: wait),
            "rate-it nudge missing"
        )

        // The unknown section is FORCED open (nothing confirmed to hide
        // behind) — no toggle tap needed to see the unknown café.
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture Unknown WiFi Cafe,")).firstMatch
                .waitForExistence(timeout: wait),
            "unknown section should already be expanded when confirmed is empty"
        )
    }

    @MainActor
    func testHonestZeroShowsEmptyStateAndResetRestores() throws {
        let app = launchSpots()

        // Every fixture's seating is KNOWN "some" — a "Plenty" floor is an
        // honest zero, not the bug.
        pick(app, identifier: "filter-seating-plenty")
        XCTAssertTrue(app.descendants(matching: .any)["map-state-empty"]
            .waitForExistence(timeout: wait),
            "Known-below-floor venues must actually filter out")

        openFilterMenuIfNeeded(app)
        let reset = app.descendants(matching: .any)["filters-reset"].firstMatch
        XCTAssertTrue(reset.waitForExistence(timeout: wait))
        reset.tap()
        XCTAssertTrue(app.mapPin(named: "Fixture Roasters").waitForExistence(timeout: wait),
                      "Reset all filters did not restore the list")
    }
}
