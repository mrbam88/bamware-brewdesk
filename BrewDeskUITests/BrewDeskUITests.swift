import XCTest

final class BrewDeskUITests: XCTestCase {
    @MainActor
    func testDiscoveryTabsExist() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-UITestSkipGates")
        app.launch()
        // brewdesk#117: exactly three tabs, identified by accessibility id
        // (not the localized label, since the label itself is also tested
        // in `testSpanishDiscoveryNavigation`).
        XCTAssertTrue(app.tabBars.buttons["tab-spots"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["tab-saved"].exists)
        XCTAssertTrue(app.tabBars.buttons["tab-you"].exists)

        // You is now the account/About surface directly — no more Saved →
        // About push.
        app.tabBars.buttons["tab-you"].tap()
        XCTAssertTrue(app.navigationBars["You"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["BrewDesk"].exists)

        // About sits below the account card + how-this-works rows now, so
        // it may not be materialized without scrolling (SwiftUI `List` is
        // lazy, same reason other tests in this suite swipe to reach a
        // below-the-fold row).
        let osmCredit = app.descendants(matching: .any)["OpenStreetMap contributors"]
        var swipes = 0
        while !osmCredit.exists, swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(osmCredit.exists)
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

        XCTAssertTrue(app.tabBars.buttons["Lugares"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Guardados"].exists)
        XCTAssertTrue(app.tabBars.buttons["Tú"].exists)
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
        // page 1's strings are exempted since this audit never swipes.
        //
        // brewdesk#98 re-tuned the Warm Utilitarian hexes: the "0X / 03"
        // page counter (`bodyTextColor` → `BrewDeskPalette.muted`,
        // `#6B5A44`) now trips the same sampling artifact — measured 6.35:1
        // sampling the audit's own captured pixels ((107,90,68) text on
        // (251,250,248) background), comfortably over 4.5:1. Added to the
        // exemption rather than darkened further: a real color change
        // wouldn't fix an anti-aliased-edge-pixel sampling issue, and the
        // two pre-existing exemptions on this screen are the same call.
        try app.performAccessibilityAudit(for: .contrast) { issue in
            guard let label = issue.element?.label else { return false }
            return label == "WORK, WITHOUT THE GUESSWORK"
                || label == "Find nearby spots where the Wi-Fi works, outlets exist, "
                + "and opening a laptop is actually welcome."
                || label == "01 / 03"
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
            // Fresh simulator containers have no persisted debug env and the
            // store falls back to .localhost — pin production so hydration
            // has a live server (found via failure hierarchy: ENV: Localhost
            // banner + "Saved spots unavailable").
            "-brewdesk.debug.environment", "production",
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["tab-spots"].waitForExistence(timeout: 8))
        app.tabBars.buttons["tab-spots"].tap()
        // Ranked, live: open whichever café is on top and carry its name.
        let top = try XCTUnwrap(app.firstMapPin(), "Spots rendered no venue pins")
        top.pin.tap()
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: 3))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Saved"].waitForExistence(timeout: 2))
        // Detail opens as a sheet from Spots (brewdesk#117) — swipe down to
        // dismiss it, then wait for Spots (and its tab bar) to actually be
        // back and interactive before tapping into it — the dismiss
        // animation briefly leaves the tab bar in the hierarchy with no
        // valid hit point.
        app.dismissDetailSheet()
        XCTAssertTrue(app.mapPins.firstMatch.waitForExistence(timeout: 5), "Spots did not survive the sheet dismiss")

        let savedTab = app.tabBars.buttons["tab-saved"]
        XCTAssertTrue(savedTab.waitForExistence(timeout: 3))
        savedTab.waitUntilHittable()
        savedTab.tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 3))
        // Saved rows are the shared VenueRow, whose children combine into
        // one labeled element ("Name, Work Fit N, Neighborhood") — there is
        // no bare StaticText with just the venue name to query (brewdesk#117).
        let savedRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", top.name)
        ).firstMatch
        XCTAssertTrue(savedRow.waitForExistence(timeout: 8),
                      "Saved tab does not list \(top.name)")
    }

    @MainActor
    func testVenueDetailAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-UITestSkipGates")
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["tab-spots"].waitForExistence(timeout: 8))
        app.tabBars.buttons["tab-spots"].tap()
        let top = try XCTUnwrap(app.firstMapPin(), "Spots rendered no venue pins")
        top.pin.tap()
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: 3))

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

        XCTAssertTrue(app.tabBars.buttons["tab-spots"].waitForExistence(timeout: 8))
        app.tabBars.buttons["tab-spots"].tap()
        let top = try XCTUnwrap(app.firstMapPin(), "Spots rendered no venue pins")
        top.pin.tap()
        XCTAssertTrue(app.descendants(matching: .any)["venue-detail-screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Workability"].exists)
        XCTAssertTrue(app.buttons["Directions"].exists)
        XCTAssertTrue(app.buttons["Save"].exists)
        XCTAssertTrue(app.buttons["Share"].exists)
    }
}
