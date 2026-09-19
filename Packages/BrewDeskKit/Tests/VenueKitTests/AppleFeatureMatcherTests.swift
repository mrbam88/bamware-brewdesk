import Foundation
import Testing
@testable import VenueKit

/// Dedupe logic for a tapped Apple base-map POI label against our own
/// listing (bd#182): same-normalized-name + within `matchRadiusMeters`.
@Suite struct AppleFeatureMatcherTests {
    private func venue(name: String, lat: Double, lng: Double) -> Venue {
        let observedAt = "2026-08-01T00:00:00Z"
        let claim = Claim(value: "fast", source: "curated", confidence: 0.9, observedAt: observedAt)
        return Venue(
            id: name,
            name: name,
            lat: lat,
            lng: lng,
            address: nil,
            neighborhood: "Test",
            borough: "Manhattan",
            hoursRaw: nil,
            vertical: "cafe",
            attributes: VenueAttributes(wifi: claim, outlets: claim, laptopPolicy: claim, noise: claim),
            vibeTags: [],
            workScore: 50,
            lastVerified: nil,
            distanceM: nil
        )
    }

    // MARK: - Matches

    @Test func exactNameAndCoordinateMatches() {
        let venues = [venue(name: "Devoción", lat: 40.7145, lng: -73.9614)]
        let match = AppleFeatureMatcher.matchingVenue(
            name: "Devoción", lat: 40.7145, lng: -73.9614, in: venues
        )
        #expect(match?.id == "Devoción")
    }

    @Test func caseAndWhitespaceInsensitiveNameStillMatches() {
        let venues = [venue(name: "Blue Bottle Coffee", lat: 40.72, lng: -73.99)]
        let match = AppleFeatureMatcher.matchingVenue(
            name: "  blue bottle coffee  ", lat: 40.72, lng: -73.99, in: venues
        )
        #expect(match != nil)
    }

    @Test func justUnderMatchRadiusStillMatches() {
        let venues = [venue(name: "Sey Coffee", lat: 40.70, lng: -73.94)]
        // ~55m north — inside the 60m radius.
        let match = AppleFeatureMatcher.matchingVenue(
            name: "Sey Coffee", lat: 40.70050, lng: -73.94, in: venues
        )
        #expect(match != nil)
    }

    // MARK: - Non-matches ("not in BrewDesk yet")

    @Test func differentNameAtSameCoordinateDoesNotMatch() {
        let venues = [venue(name: "Devoción", lat: 40.7145, lng: -73.9614)]
        let match = AppleFeatureMatcher.matchingVenue(
            name: "Some Other Café", lat: 40.7145, lng: -73.9614, in: venues
        )
        #expect(match == nil)
    }

    @Test func sameNameFarAwayDoesNotMatch() {
        let venues = [venue(name: "Blue Bottle Coffee", lat: 40.72, lng: -73.99)]
        // A different, real "Blue Bottle Coffee" a mile away is not this one.
        let match = AppleFeatureMatcher.matchingVenue(
            name: "Blue Bottle Coffee", lat: 40.75, lng: -73.98, in: venues
        )
        #expect(match == nil)
    }

    @Test func justOverMatchRadiusDoesNotMatch() {
        let venues = [venue(name: "Sey Coffee", lat: 40.70, lng: -73.94)]
        // ~78m north — outside the 60m radius.
        let match = AppleFeatureMatcher.matchingVenue(
            name: "Sey Coffee", lat: 40.70070, lng: -73.94, in: venues
        )
        #expect(match == nil)
    }

    @Test func emptyListingNeverMatches() {
        #expect(AppleFeatureMatcher.matchingVenue(name: "Anything", lat: 0, lng: 0, in: []) == nil)
    }

    @Test func emptyFeatureNameNeverMatches() {
        let venues = [venue(name: "Devoción", lat: 40.7145, lng: -73.9614)]
        let match = AppleFeatureMatcher.matchingVenue(name: "  ", lat: 40.7145, lng: -73.9614, in: venues)
        #expect(match == nil)
    }
}
