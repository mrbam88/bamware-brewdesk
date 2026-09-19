import Foundation
import Testing
@testable import VenueKit

/// bd#182: no venue-engine "suggest a new café" endpoint exists today
/// (checked `VenueAPI.swift` — every observation/photo route requires an
/// existing `venueId`), so the card's action calls this documented stub
/// instead. These tests exist to pin that it's a genuine no-op — never a
/// silent throw, never a fabricated success that masks a real wire call.
@Suite struct CafeSuggestionContractTests {
    @Test func nullClientSucceedsWithoutThrowing() async throws {
        let client = NullCafeSuggestionClient()
        try await client.suggestCafe(CafeSuggestion(name: "Corner Café", lat: 40.71, lng: -74.00))
    }

    @Test func suggestionDefaultsToAppleMapsSource() {
        let suggestion = CafeSuggestion(name: "Corner Café", lat: 40.71, lng: -74.00)
        #expect(suggestion.source == "apple-maps")
    }
}
