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

    func mapPin(named name: String) -> XCUIElement {
        buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
    }

    /// Nearby rows are combined accessibility elements labelled
    /// "<name>, Work Fit <n>, <neighborhood>, Wi-Fi <v>, outlets <v>"
    /// (CafeListScreen.VenueRow).
    var venueRows: XCUIElementQuery {
        buttons.matching(NSPredicate(format: "label CONTAINS %@", ", Wi-Fi "))
    }

    /// The top-ranked row currently on screen and its venue name, so a test
    /// can open it and later assert on that same name (e.g. in Saved).
    func firstVenueRow(timeout: TimeInterval = 15) -> (row: XCUIElement, name: String)? {
        let row = venueRows.firstMatch
        guard row.waitForExistence(timeout: timeout),
              let name = row.label.components(separatedBy: ", Work Fit ").first,
              !name.isEmpty
        else { return nil }
        return (row, name)
    }
}
