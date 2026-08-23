import XCTest

final class BrewDeskUITests: XCTestCase {
    @MainActor
    func testDiscoveryTabsExist() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-UITestSkipGates")
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Nearby"].exists)
        XCTAssertTrue(app.tabBars.buttons["Saved"].exists)

        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 2))
        app.buttons["About"].tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["BrewDesk"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["OpenStreetMap contributors"].exists)
    }

    @MainActor
    func testSpanishDiscoveryNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-AppleLanguages", "(es)",
            "-AppleLocale", "es_US",
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Explorar"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Cercanos"].exists)
        XCTAssertTrue(app.tabBars.buttons["Guardados"].exists)
    }

    @MainActor
    func testOnboardingAtAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-brewdesk.onboarding.complete", "NO",
            "-brewdesk.location-intro.complete", "NO",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Your next desk might serve espresso."].exists)
    }

    @MainActor
    func testOnboardingAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-brewdesk.onboarding.complete", "NO",
            "-brewdesk.location-intro.complete", "NO",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 8))

        // Onboarding's background is a LinearGradient (brewdesk#75, dark
        // mode support); the audit mis-samples text against it as a contrast
        // failure even though the real composited contrast is comfortably
        // over WCAG 1.4.3 (measured: eyebrow 8.28:1, body 9.98:1, sampling
        // the actual PNG pixels the audit itself captured — see
        // docs/ui-review-2026-08-22.md). Same false-positive class the dock/
        // material exemptions elsewhere in this file already document; only
        // page 1's two strings are exempted since this audit never swipes.
        try app.performAccessibilityAudit(for: .contrast) { issue in
            guard let label = issue.element?.label else { return false }
            return label == "WORK, WITHOUT THE GUESSWORK"
                || label == "Find nearby cafes where the Wi-Fi works, outlets exist, "
                + "and opening a laptop is actually welcome."
        }
        try app.performAccessibilityAudit(
            for: [.dynamicType, .elementDetection, .hitRegion, .sufficientElementDescription, .textClipped, .trait]
        )
    }

    @MainActor
    func testSaveCafeFromDetails() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            "-brewdesk.saved-venue-ids", "",
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Nearby"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Nearby"].tap()
        // Ranked list: open whichever café is on top and carry its name.
        let top = try XCTUnwrap(app.firstVenueRow(), "Nearby list rendered no venue rows")
        top.row.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 3))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Saved"].waitForExistence(timeout: 2))

        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts[top.name].waitForExistence(timeout: 8),
                      "Saved tab does not list \(top.name)")
    }

    @MainActor
    func testVenueDetailAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-UITestSkipGates")
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Nearby"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Nearby"].tap()
        let top = try XCTUnwrap(app.firstVenueRow(), "Nearby list rendered no venue rows")
        top.row.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 3))

        // The floating action dock (Directions/Save/Share) is translucent
        // glass; content legitimately scrolls beneath it, and the audit
        // samples those washed-out pixels as contrast failures. Ignore
        // issues for elements occluded by the dock — everything else must
        // still pass (bd#36 diagnosis, 2026-08-21).
        // Inset by the dock's glass halo. −20 covered the shadow reach
        // (radius 14, y −3), but iOS 26 Liquid Glass also *refracts* content
        // approaching the edge: measured on 17 Pro Max (bd#62 diagnosis,
        // 2026-08-21), the audit flagged a claim row whose frame ended 31pt
        // above the dock's real top edge — black text on cream, unfailable
        // anywhere else on the page, washed only by the lens band. −56 covers
        // the measured reach with margin; everything outside it must still pass.
        let dockFrame = app.otherElements["action-dock"].exists
            ? app.otherElements["action-dock"].frame.insetBy(dx: 0, dy: -56)
            : CGRect.null
        // The translucent tab bar washes scrolled-under content the same way
        // the dock does (first seen on 17e, bd#50; hit 17 Pro once bd#47's
        // entry card made the page taller). Same occlusion class, same rule.
        let tabBarFrame = app.tabBars.firstMatch.exists
            ? app.tabBars.firstMatch.frame.insetBy(dx: 0, dy: -20)
            : CGRect.null
        try app.performAccessibilityAudit(for: [
            .contrast,
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .textClipped,
            .trait,
        ]) { issue in
            guard let element = issue.element else { return false }
            let frame = element.frame
            return (!dockFrame.isNull && frame.intersects(dockFrame))
                || (!tabBarFrame.isNull && frame.intersects(tabBarFrame))
        }
    }

    @MainActor
    func testVenueDetailAtAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestSkipGates",
            // The top-ranked venue may have been saved by an earlier test in
            // this run; start unsaved so the button reads "Save", not "Saved".
            "-brewdesk.saved-venue-ids", "",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Nearby"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Nearby"].tap()
        let top = try XCTUnwrap(app.firstVenueRow(), "Nearby list rendered no venue rows")
        top.row.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Workability"].exists)
        XCTAssertTrue(app.buttons["Directions"].exists)
        XCTAssertTrue(app.buttons["Save"].exists)
        XCTAssertTrue(app.buttons["Share"].exists)
    }
}
