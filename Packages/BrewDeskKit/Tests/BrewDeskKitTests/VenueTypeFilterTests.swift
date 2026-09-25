import Foundation
import Testing
@testable import BrewDeskKit
import VenueKit

/// brewdesk#240 — "Place type" as a first-class filter: the multi-select
/// matrix (`VenueFilter.classify`/`matches` across every combination of the
/// four chips), `WorkFitFilterMenu.activeFilterCount` (the filter badge's
/// number), and `VenuesModel`'s header-facing counts
/// (`hasActiveFilter`/`confirmedCount`/`unknownCount`, and `venues.count` —
/// the inputs `CafeMapScreen`'s "N rated · M cafés" / "N match · M unknown"
/// header line reads from). `FilterClassificationTests` and
/// `FilterInclusivityTests` already cover the single-type-selected cases in
/// depth; this suite is the multi-select combination matrix plus the
/// count-surfacing contract.
@Suite @MainActor struct VenueTypeFilterMatrixTests {
    private static let observedAt = "2026-08-01T00:00:00Z"

    private static func venue(id: String, venueType: String?) -> Venue {
        func claim(_ value: String) -> Claim {
            Claim(value: value, source: "curated", confidence: 0.8, observedAt: observedAt)
        }
        return Venue(
            id: id, name: id, lat: 40.7359, lng: -73.9911, address: nil,
            neighborhood: "Union Square", borough: "Manhattan", hoursRaw: nil, vertical: "cafe",
            attributes: VenueAttributes(
                wifi: claim("fast"), outlets: claim("plenty"), laptopPolicy: claim("unrestricted"),
                noise: claim("moderate"), seating: claim("plenty")
            ),
            vibeTags: [], workScore: 70, lastVerified: nil, distanceM: nil, venueType: venueType
        )
    }

    private static let cafe = venue(id: "cafe", venueType: "cafe")
    private static let library = venue(id: "library", venueType: "library")
    private static let park = venue(id: "park", venueType: "park")
    private static let coworking = venue(id: "coworking", venueType: "other")
    private static let all = [cafe, library, park, coworking]

    // MARK: - Multi-select matrix

    @Test func allFourSelectedIsNoFilterEveryTypeMatches() {
        let filter = VenueFilter(selectedVenueTypes: Set(VenueTypeBadge.filterableCases))
        for venue in Self.all {
            #expect(filter.classify(venue) == .confirmed, "\(venue.id) should be confirmed with no type constraint")
        }
    }

    @Test func singleTypeSelectionsMatchOnlyThatType() {
        for type in VenueTypeBadge.filterableCases {
            let filter = VenueFilter(selectedVenueTypes: [type])
            for venue in Self.all {
                let expected: VenueFilter.FilterMatch = venue.typeBadge == type ? .confirmed : .excluded
                #expect(
                    filter.classify(venue) == expected,
                    "\(venue.id) under \(type) filter: expected \(expected)"
                )
            }
        }
    }

    @Test func twoTypesSelectedMatchesBoth() {
        let filter = VenueFilter(selectedVenueTypes: [.cafe, .park])
        #expect(filter.classify(Self.cafe) == .confirmed)
        #expect(filter.classify(Self.park) == .confirmed)
        #expect(filter.classify(Self.library) == .excluded)
        #expect(filter.classify(Self.coworking) == .excluded)
    }

    @Test func threeTypesSelectedExcludesOnlyTheFourth() {
        let filter = VenueFilter(selectedVenueTypes: [.cafe, .library, .park])
        #expect(filter.classify(Self.cafe) == .confirmed)
        #expect(filter.classify(Self.library) == .confirmed)
        #expect(filter.classify(Self.park) == .confirmed)
        #expect(filter.classify(Self.coworking) == .excluded)
    }

    @Test func emptySelectionExcludesEveryKnownType() {
        let filter = VenueFilter(selectedVenueTypes: [])
        for venue in Self.all {
            #expect(filter.classify(venue) == .excluded, "\(venue.id) should be excluded by an empty selection")
        }
    }

    // MARK: - Header/model counts

    private func loadedModel(_ venues: [Venue]) async -> VenuesModel {
        struct FixtureService: VenueListing {
            let venues: [Venue]
            func fetchVenues(_ query: VenueQuery) async throws -> [Venue] { venues }
        }
        let model = VenuesModel(api: FixtureService(venues: venues))
        await model.load(model.request)
        return model
    }

    @Test func narrowingToParksLeavesOnlyTheParkInVenues() async {
        let model = await loadedModel(Self.all)
        #expect(model.venues.count == 4)

        model.selectedVenueTypes = [.park]
        #expect(model.venues.map(\.id) == ["park"])
    }

    @Test func resettingSelectionRestoresEveryVenue() async {
        let model = await loadedModel(Self.all)
        model.selectedVenueTypes = [.cafe]
        #expect(model.venues.count == 1)

        model.selectedVenueTypes = Set(VenueTypeBadge.filterableCases)
        #expect(model.venues.count == 4)
    }

    // MARK: - `WorkFitFilterMenu.activeFilterCount` (the filter badge's number)

    @Test func activeFilterCountIsZeroWithEveryChipOn() {
        let model = VenuesModel(api: EmptyVenueService())
        #expect(WorkFitFilterMenu.activeFilterCount(model) == 0)
    }

    @Test func activeFilterCountCountsANarrowedTypeSelectionAsOne() {
        let model = VenuesModel(api: EmptyVenueService())
        model.selectedVenueTypes = [.cafe, .park]
        #expect(WorkFitFilterMenu.activeFilterCount(model) == 1)

        // Deselecting a SECOND chip still counts as exactly one active
        // filter — one row, one count, matching every other dimension.
        model.selectedVenueTypes = [.cafe]
        #expect(WorkFitFilterMenu.activeFilterCount(model) == 1)
    }

    @Test func activeFilterCountAddsToOtherDimensions() {
        let model = VenuesModel(api: EmptyVenueService())
        model.laptopFriendlyOnly = true
        model.minWifi = .fast
        model.selectedVenueTypes = [.library]
        #expect(WorkFitFilterMenu.activeFilterCount(model) == 3)
    }

    // MARK: - `hasActiveFilter` / the honest confirmed·unknown header split

    /// brewdesk#240: a TYPE-ONLY filter now flips `hasActiveFilter` too —
    /// the header line and shelf switch to the confirmed/unknown split
    /// exactly like every other dimension already does, so a narrowed type
    /// selection's count is visible the same way brewdesk#222's "N match ·
    /// M unknown" is.
    @Test func typeOnlyFilterCountsAsAnActiveFilter() async {
        let model = await loadedModel(Self.all)
        #expect(!model.hasActiveFilter)

        model.selectedVenueTypes = [.park]
        #expect(model.hasActiveFilter)
        #expect(model.confirmedCount == 1)
        #expect(model.confirmedVenues.map(\.id) == ["park"])
    }
}

private struct EmptyVenueService: VenueListing {
    func fetchVenues(_ query: VenueQuery) async throws -> [Venue] { [] }
}
