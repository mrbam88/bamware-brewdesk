import Foundation
import Testing
@testable import BrewDeskKit
import VenueKit

/// `VenueOrdering.observedFirst` (bd#159): a stable partition, not a sort —
/// observed venues come first, unobserved ones last, and each group keeps
/// its own relative order untouched.
@Suite struct VenueOrderingTests {
    private static let observedAt = "2026-08-01T00:00:00Z"

    private static func venue(id: String, observed: Bool, workScore: Int = 52) -> Venue {
        let claim = Claim(
            value: "fast",
            source: observed ? "curated" : "estimate",
            confidence: observed ? 0.8 : 0.2,
            observedAt: observedAt
        )
        return Venue(
            id: id,
            name: id,
            lat: 40.7,
            lng: -74.0,
            address: nil,
            neighborhood: "SoHo",
            borough: "Manhattan",
            hoursRaw: nil,
            vertical: "cafe",
            attributes: VenueAttributes(wifi: claim, outlets: claim, laptopPolicy: claim, noise: claim),
            vibeTags: [],
            workScore: workScore,
            lastVerified: nil,
            distanceM: nil
        )
    }

    @Test func observedVenuesSortBeforeUnobservedOnes() {
        let venues = [
            Self.venue(id: "unobserved-1", observed: false),
            Self.venue(id: "observed-1", observed: true),
            Self.venue(id: "unobserved-2", observed: false),
            Self.venue(id: "observed-2", observed: true),
        ]

        let result = VenueOrdering.observedFirst(venues)

        #expect(result.map(\.id) == ["observed-1", "observed-2", "unobserved-1", "unobserved-2"])
    }

    @Test func partitionIsStableWithinEachGroup() {
        // Server order inside each group must survive untouched, even when
        // an unobserved venue's workScore is HIGHER than an observed one's
        // (the whole point: score alone must never re-rank across groups).
        let venues = [
            Self.venue(id: "o-low", observed: true, workScore: 40),
            Self.venue(id: "u-high", observed: false, workScore: 90),
            Self.venue(id: "o-high", observed: true, workScore: 95),
            Self.venue(id: "u-low", observed: false, workScore: 10),
        ]

        let result = VenueOrdering.observedFirst(venues)

        #expect(result.map(\.id) == ["o-low", "o-high", "u-high", "u-low"])
    }

    @Test func allObservedOrAllUnobservedIsUnchanged() {
        let allObserved = (0..<3).map { Self.venue(id: "o\($0)", observed: true) }
        #expect(VenueOrdering.observedFirst(allObserved).map(\.id) == allObserved.map(\.id))

        let allUnobserved = (0..<3).map { Self.venue(id: "u\($0)", observed: false) }
        #expect(VenueOrdering.observedFirst(allUnobserved).map(\.id) == allUnobserved.map(\.id))
    }

    @Test func emptyInputStaysEmpty() {
        #expect(VenueOrdering.observedFirst([]).isEmpty)
    }

    /// The composition order the issue calls out: filter, then search, then
    /// the observed/unobserved partition — a search match rank still wins
    /// INSIDE each group.
    @Test func composesAfterSearchSoMatchRankWinsInsideEachGroup() {
        var prefixObserved = Self.venue(id: "prefix-observed", observed: true)
        var containsObserved = Self.venue(id: "z-contains-observed", observed: true)
        var prefixUnobserved = Self.venue(id: "prefix-unobserved", observed: false)
        var containsUnobserved = Self.venue(id: "z-contains-unobserved", observed: false)
        // Rename so "prefix" search terms actually rank as prefix matches.
        prefixObserved = Self.renamed(prefixObserved, "Prefix Cafe")
        containsObserved = Self.renamed(containsObserved, "A Prefix-Adjacent Cafe")
        prefixUnobserved = Self.renamed(prefixUnobserved, "Prefix Diner")
        containsUnobserved = Self.renamed(containsUnobserved, "A Prefix-Adjacent Diner")

        // Server order deliberately puts the "contains" match first in each
        // group; search must still rank the prefix match ahead of it.
        let venues = [containsObserved, prefixObserved, containsUnobserved, prefixUnobserved]

        let result = VenueOrdering.observedFirst(VenueSearch.apply("prefix", to: venues))

        #expect(result.map(\.name) == [
            "Prefix Cafe", "A Prefix-Adjacent Cafe",
            "Prefix Diner", "A Prefix-Adjacent Diner",
        ])
    }

    private static func renamed(_ venue: Venue, _ name: String) -> Venue {
        Venue(
            id: venue.id,
            name: name,
            lat: venue.lat,
            lng: venue.lng,
            address: venue.address,
            neighborhood: venue.neighborhood,
            borough: venue.borough,
            hoursRaw: venue.hoursRaw,
            vertical: venue.vertical,
            attributes: venue.attributes,
            vibeTags: venue.vibeTags,
            workScore: venue.workScore,
            lastVerified: venue.lastVerified,
            distanceM: venue.distanceM
        )
    }
}
