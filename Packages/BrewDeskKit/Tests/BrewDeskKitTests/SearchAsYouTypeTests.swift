import Foundation
import Testing
@testable import BrewDeskKit
import VenueKit

/// brewdesk#78 — search-as-you-type. Semantics under test:
///
/// - Typing filters the already-loaded list ~200ms after the last keystroke —
///   no submit needed, and never a network request per keystroke.
/// - Matching is case- and diacritic-insensitive, prefix + contains, over
///   venue name and neighborhood. Prefix matches rank first.
/// - Submit (keyboard Search key) and clear apply immediately.
/// - No matches yields an empty list (the views' loaded-empty state).
@Suite @MainActor struct SearchAsYouTypeTests {
    private static let roasters = searchFixtureVenue(name: "Café Añejo Roasters", neighborhood: "Union Square")
    private static let readingRoom = searchFixtureVenue(name: "Reading Room", neighborhood: "Greenwich Village")
    private static let bottleHouse = searchFixtureVenue(name: "Bottle House", neighborhood: "Flatiron")
    private static let blueBottle = searchFixtureVenue(name: "Blue Bottle", neighborhood: "NoHo")
    private static let all = [roasters, readingRoom, bottleHouse, blueBottle]

    private func loadedModel(_ api: CountingVenueService) async -> VenuesModel {
        let model = VenuesModel(api: api)
        await model.load(model.request)
        return model
    }

    private func names(_ model: VenuesModel) -> [String] {
        model.venues.map(\.name)
    }

    /// The debounce is ~200ms; give it 5x before calling the apply missing.
    private func waitForDebounce() async throws {
        try await Task.sleep(for: .milliseconds(1_000))
    }

    @Test func typingAppliesAfterDebounceWithoutNetworkOrSubmit() async throws {
        let api = CountingVenueService(venues: Self.all)
        let model = await loadedModel(api)
        let fetchesAfterLoad = await api.fetchCount

        model.searchQuery = "reading"
        #expect(names(model) == Self.all.map(\.name))   // not yet — debounced

        try await waitForDebounce()
        #expect(names(model) == ["Reading Room"])       // applied, no submit
        #expect(model.request.query.search == nil)      // never on the wire
        #expect(await api.fetchCount == fetchesAfterLoad)
    }

    @Test func matchingIsCaseAndDiacriticInsensitive() async throws {
        let model = await loadedModel(CountingVenueService(venues: Self.all))

        model.searchQuery = "CAFE ANEJO"
        try await waitForDebounce()
        #expect(names(model) == ["Café Añejo Roasters"])
    }

    @Test func neighborhoodMatchesToo() async throws {
        let model = await loadedModel(CountingVenueService(venues: Self.all))

        model.searchQuery = "greenwich"
        try await waitForDebounce()
        #expect(names(model) == ["Reading Room"])
    }

    @Test func prefixMatchesRankBeforeContainsMatches() async throws {
        let model = await loadedModel(CountingVenueService(venues: Self.all))

        model.searchQuery = "bottle"
        try await waitForDebounce()
        #expect(names(model) == ["Bottle House", "Blue Bottle"])
    }

    @Test func submitAppliesImmediately() async {
        let model = await loadedModel(CountingVenueService(venues: Self.all))

        model.searchQuery = "  reading  "
        model.submitSearch()
        #expect(names(model) == ["Reading Room"])       // no debounce wait
    }

    @Test func clearRestoresImmediately() async {
        let model = await loadedModel(CountingVenueService(venues: Self.all))

        model.searchQuery = "reading"
        model.submitSearch()
        #expect(names(model) == ["Reading Room"])

        model.clearSearch()
        #expect(model.searchQuery.isEmpty)
        #expect(names(model) == Self.all.map(\.name))   // no debounce wait
    }

    @Test func noMatchesYieldsEmptyLoadedList() async {
        let model = await loadedModel(CountingVenueService(venues: Self.all))

        model.searchQuery = "zzz nowhere"
        model.submitSearch()
        #expect(model.venues.isEmpty)
        #expect(model.phase == .loaded)                 // views show empty-state
    }

    @Test func whitespaceOnlyQueryMatchesEverything() async {
        let model = await loadedModel(CountingVenueService(venues: Self.all))

        model.searchQuery = "   "
        model.submitSearch()
        #expect(names(model) == Self.all.map(\.name))
    }

    @Test func searchStacksWithCategoryFilters() async {
        let model = await loadedModel(CountingVenueService(venues: Self.all))

        model.venueType = .cafe                          // all fixtures default to cafe
        model.searchQuery = "bottle"
        model.submitSearch()
        #expect(names(model) == ["Bottle House", "Blue Bottle"])

        model.venueType = .library
        #expect(model.venues.isEmpty)
    }
}

// MARK: - Fixtures

private actor CountingVenueService: VenueListing {
    let venues: [Venue]
    private(set) var fetchCount = 0

    init(venues: [Venue]) {
        self.venues = venues
    }

    func fetchVenues(_ query: VenueQuery) async throws -> [Venue] {
        fetchCount += 1
        return venues
    }
}

private func searchFixtureVenue(name: String, neighborhood: String) -> Venue {
    let observedAt = "2026-08-01T00:00:00Z"
    func claim(_ value: String) -> Claim {
        Claim(value: value, source: "curated", confidence: 0.8, observedAt: observedAt)
    }
    return Venue(
        id: name,
        name: name,
        lat: 40.7359,
        lng: -73.9911,
        address: nil,
        neighborhood: neighborhood,
        borough: "Manhattan",
        hoursRaw: nil,
        vertical: "cafe",
        attributes: VenueAttributes(
            wifi: claim("fast"),
            outlets: claim("plenty"),
            laptopPolicy: claim("unrestricted"),
            noise: claim("moderate")
        ),
        vibeTags: [],
        workScore: 70,
        lastVerified: nil,
        distanceM: nil
    )
}
