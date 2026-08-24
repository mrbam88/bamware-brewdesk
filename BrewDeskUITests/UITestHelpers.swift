import XCTest

/// Rank-independent matchers for live-data UI tests. The production dataset
/// re-ranks venues whenever scoring evidence changes (brewdesk#37), so tests
/// must never wait for a specific café to be on screen — match the shape of
/// the element instead and carry the name that happens to be there.
extension XCUIApplication {
    /// Map pins are buttons labelled "<name>, Work Fit <n>, <neighborhood>"
    /// (CafeMapScreen).
    var mapPins: XCUIElementQuery {
        buttons.matching(NSPredicate(format: "label CONTAINS %@", ", Work Fit "))
    }

    /// A venue can match this predicate twice at once — the shelf's rail
    /// card (always on-screen at the default camera position) and the real
    /// MapKit pin (which may currently be panned out of the visible
    /// viewport, e.g. a venue in a different neighborhood than the map's
    /// center). `.firstMatch` picks whichever the AX tree happens to list
    /// first, which is not guaranteed to be the one actually on screen.
    /// Prefer whichever match's frame actually falls inside the window —
    /// deliberately a plain geometry read, not `.isHittable`: XCUITest
    /// records a hard test failure (not just `false`) when `.isHittable`
    /// hit-tests an off-viewport MapKit annotation with no computable
    /// activation point.
    func mapPin(named name: String) -> XCUIElement {
        let matches = buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ","))
        return Self.firstOnScreenMatch(in: matches, windowFrame: windows.firstMatch.frame) ?? matches.firstMatch
    }

    fileprivate static func firstOnScreenMatch(in query: XCUIElementQuery, windowFrame: CGRect) -> XCUIElement? {
        for index in 0..<query.count {
            let candidate = query.element(boundBy: index)
            let frame = candidate.frame
            if !frame.isEmpty, windowFrame.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                return candidate
            }
        }
        return nil
    }

    /// Nearby rows were combined accessibility elements labelled
    /// "<name>, Work Fit <n>, <neighborhood>, Wi-Fi <v>, outlets <v>"
    /// (CafeListScreen.VenueRow) — kept for whatever list surface
    /// brewdesk#118 lands; the Nearby tab that hosted it is gone
    /// (brewdesk#117), so nothing in the current tab set matches this any
    /// more. Use `mapPins`/`firstMapPin` instead.
    var venueRows: XCUIElementQuery {
        buttons.matching(NSPredicate(format: "label CONTAINS %@", ", Wi-Fi "))
    }

    /// The top-ranked row currently on screen and its venue name, so a test
    /// can open it and later assert on that same name (e.g. in Saved).
    /// Kept alongside `venueRows` for the same reason.
    func firstVenueRow(timeout: TimeInterval = 15) -> (row: XCUIElement, name: String)? {
        let row = venueRows.firstMatch
        guard row.waitForExistence(timeout: timeout),
              let name = row.label.components(separatedBy: ", Work Fit ").first,
              !name.isEmpty
        else { return nil }
        return (row, name)
    }

    /// brewdesk#117: the Spots tab's map pins and shelf cards share this
    /// label shape, so this is the rank-independent "top venue on Spots"
    /// helper — the direct replacement for `firstVenueRow` now that Nearby
    /// is gone. Prefers a hittable match for the same reason `mapPin(named:)`
    /// does: the first AX-tree match is not guaranteed to be the one
    /// actually on screen (shelf card vs. a panned-out-of-view map pin).
    func firstMapPin(timeout: TimeInterval = 15) -> (pin: XCUIElement, name: String)? {
        let query = mapPins
        guard query.firstMatch.waitForExistence(timeout: timeout) else { return nil }
        let pin = Self.firstOnScreenMatch(in: query, windowFrame: windows.firstMatch.frame) ?? query.firstMatch
        guard let name = pin.label.components(separatedBy: ", Work Fit ").first, !name.isEmpty
        else { return nil }
        return (pin, name)
    }
}

extension XCUIElement {
    /// `.exists` can be true while a sheet-dismiss animation is still
    /// settling underneath (brewdesk#117: venue detail is a sheet over
    /// Spots now) — the element is in the hierarchy but its frame hasn't
    /// caught up yet, so an immediate `.tap()` computes an invalid hit
    /// point. Poll `.isHittable` instead of a fixed sleep.
    @discardableResult
    func waitUntilHittable(timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return isHittable
    }
}

extension XCUIApplication {
    /// brewdesk#117: venue detail opens as a sheet from Spots, defaulting
    /// to `.large` (see `CafeMapScreen`) so its content isn't crowded. A
    /// single `swipeDown()` from `.large` only steps the sheet down to
    /// `.medium` — sheets step through detents on drag, they don't jump
    /// straight to dismiss — so getting back to Spots (and its now-covered
    /// tab bar) needs another swipe. Repeats until "Details" is actually
    /// gone rather than assuming a fixed count.
    @discardableResult
    func dismissDetailSheet(timeout: TimeInterval = 5) -> Bool {
        guard navigationBars["Details"].exists else { return true }
        // `.presentationContentInteraction(.scrolls)` routes swipes to the
        // detail scroll view, so gestures can't reliably dismiss the sheet —
        // use its explicit Close button (brewdesk#117), swipe as fallback.
        let close = buttons["detail-close"]
        if close.waitForExistence(timeout: 2), close.isHittable {
            close.tap()
        } else {
            swipeDown()
        }
        return navigationBars["Details"].waitForNonExistence(timeout: timeout)
    }
}
