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

    @MainActor
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

    // MARK: The "Saved" title must actually be drawn

    /// The large "Saved" title is in the accessibility tree even when
    /// something opaque is painted over it (that is how it went missing
    /// once: the pinned sync line's background covered it and every
    /// existence check still passed). So this reads the pixels: the title's
    /// own frame must contain ink that contrasts with its background.
    @MainActor
    private func assertSavedTitleIsDrawn(_ app: XCUIApplication, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        let title = app.navigationBars.staticTexts["Saved"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: wait), "\(context): no \"Saved\" title element", file: file, line: line)
        let frame = title.frame
        XCTAssertFalse(frame.isEmpty, "\(context): the title has no frame", file: file, line: line)

        let ink = Self.inkFraction(of: app.screenshot().image, in: frame, windowSize: app.windows.firstMatch.frame.size)
        XCTAssertGreaterThan(
            ink, 0.03,
            "\(context): the \"Saved\" title's frame \(frame) is blank (ink \(ink)); something is drawn over it",
            file: file, line: line
        )
    }

    /// Share of pixels in `rect` (window points) whose brightness differs
    /// clearly from the rect's own top-left pixel, i.e. text on a flat fill.
    private static func inkFraction(of image: UIImage, in rect: CGRect, windowSize: CGSize) -> Double {
        guard let source = image.cgImage, windowSize.width > 0 else { return 0 }
        let scale = CGFloat(source.width) / windowSize.width
        let crop = CGRect(
            x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale
        ).integral
        guard let cropped = source.cropping(to: crop) else { return 0 }
        let width = cropped.width, height = cropped.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        func brightness(_ index: Int) -> Double {
            (0.299 * Double(pixels[index]) + 0.587 * Double(pixels[index + 1]) + 0.114 * Double(pixels[index + 2])) / 255
        }
        let background = brightness(0)
        var inked = 0
        for pixel in 0..<(width * height) where abs(brightness(pixel * 4) - background) > 0.4 {
            inked += 1
        }
        return Double(inked) / Double(max(width * height, 1))
    }

    @MainActor
    func testSavedTitleIsDrawnWithPicksAndWithout() {
        for (scenario, saved, context) in [
            ("onePick", "()", "one pick, nothing saved"),
            ("tenPicks", "(\"fixture-pick-4\")", "ten picks"),
            ("fixtureOK", "()", "no picks, nothing saved"),
            ("fixtureOK", "(\"fixture-roasters\")", "no picks, one saved spot"),
        ] {
            let app = launch(scenario, savedIDs: saved)
            if scenario != "fixtureOK" {
                XCTAssertTrue(app.staticTexts["Bamware Picks"].waitForExistence(timeout: wait), context)
            } else if saved == "()" {
                XCTAssertTrue(element(app, "saved-state-empty").waitForExistence(timeout: wait), context)
            } else {
                XCTAssertTrue(app.staticTexts["Fixture Roasters"].waitForExistence(timeout: wait), context)
            }
            assertSavedTitleIsDrawn(app, context)
            // And the sync line under it still says what it should, signed out.
            let sync = element(app, "saved-sync-status")
            XCTAssertTrue(sync.exists, context)
            XCTAssertEqual(sync.label, "Local only", context)
            app.terminate()
        }
    }

    @MainActor
    func testSavedTitleCollapsesIntoTheBarWhenThePicksListScrolls() {
        let app = launch("tenPicks", savedIDs: "(\"fixture-pick-4\")")
        XCTAssertTrue(app.staticTexts["Bamware Picks"].waitForExistence(timeout: wait))
        let title = app.navigationBars.staticTexts["Saved"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: wait))
        let restingY = title.frame.midY
        let restingHeight = title.frame.height

        app.swipeUp()
        app.swipeUp()

        // Collapsed: a smaller title, higher up, centred in the bar, and
        // still drawn; the sync line stays pinned beneath it.
        XCTAssertTrue(title.exists)
        XCTAssertLessThan(title.frame.midY, restingY, "the title did not move up into the bar")
        XCTAssertLessThan(title.frame.height, restingHeight, "the title did not shrink")
        XCTAssertEqual(title.frame.midX, app.windows.firstMatch.frame.midX, accuracy: 12)
        assertSavedTitleIsDrawn(app, "ten picks, scrolled")
        XCTAssertEqual(element(app, "saved-sync-status").label, "Local only")
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
