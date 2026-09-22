import Foundation
import Testing
@testable import BrewDeskKit
import VenueKit

/// brewdesk#78 — search-as-you-type. Semantics under test:
///
/// - Typing filters the already-loaded list ~200ms after the last keystroke —
///   no submit needed, and (still) never a network request per keystroke:
///   bd#200's citywide server search shares the exact same settle signal
///   (`activeSearchText`), so it fires once per SETTLED query, not once per
///   character — see `typingAppliesAfterDebounceWithoutNetworkOrSubmit`.
/// - Matching is case- and diacritic-insensitive, prefix + contains, over
///   venue name and neighborhood. Prefix matches rank first.
/// - Submit (keyboard Search key) and clear apply immediately.
/// - No matches yields an empty list (the views' loaded-empty state).
///
/// `CountingVenueService` now honors `query.search` (bd#200): every other
/// query field it already ignored (filters, sort, limit), matching the
/// pre-existing "the wire predicate is whatever the fake decides" contract
/// these tests were written against — only `search` needed real behavior so
/// the citywide-search union logic under test here has something real to
/// union against.
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

    /// Deterministically waits for the pending debounce — and, once it
    /// settles a non-empty query, the resulting citywide server search — to
    /// finish, instead of sleeping a fixed real-time margin.
    ///
    /// bd#226 CI flake, root-caused by bisecting `SearchAsYouTypeTests`
    /// against the exact commits `main`'s CI ran green/red at (7a2f17c,
    /// 593c623, a5bd87d): every commit passes these tests in isolation
    /// (`-only-testing:…/SearchAsYouTypeTests`); running the FULL
    /// BrewDeskKit-Package suite is what makes them flake, and which of the
    /// ~340 tests loses the race is different every run (also caught:
    /// `CityWideSearchTests`, `CoverageStateTests`,
    /// `snapshotIsNeverReseededAfterALiveAnswer`, all pre-existing
    /// deadline/sleep-based waits, and reproducible back at 593c623 itself
    /// with a different victim test) — this was never a semantic merge
    /// conflict between #225's search and #226's filter-honesty split; the
    /// suite simply grew past the margin a blind `Task.sleep(1_000ms)` (5x
    /// the ~200ms debounce) needs once enough parallel `@MainActor` tests
    /// contend for the same executor.
    ///
    /// Awaiting the model's own debounce/server Tasks (`searchDebounceTask`/
    /// `serverSearchTask`, made test-visible in `VenuesModel`) removes the
    /// real-time guess entirely: this returns exactly when the production
    /// code actually settles, however long the scheduler took to get there.
    private func waitForDebounce(_ model: VenuesModel) async {
        await model.searchDebounceTask?.value
        await model.serverSearchTask?.value
    }

    @Test func typingAppliesAfterDebounceWithoutNetworkOrSubmit() async throws {
        let api = CountingVenueService(venues: Self.all)
        let model = await loadedModel(api)
        let fetchesAfterLoad = await api.fetchCount

        model.searchQuery = "reading"
        #expect(names(model) == Self.all.map(\.name))   // not yet — debounced

        await waitForDebounce(model)
        #expect(names(model) == ["Reading Room"])       // applied, no submit
        #expect(model.request.query.search == nil)      // the VIEWPORT request never carries it
        // bd#200: exactly ONE citywide request for the settled query — not
        // one per keystroke, and not zero either (that was the bug).
        #expect(await api.fetchCount == fetchesAfterLoad + 1)
    }

    @Test func matchingIsCaseAndDiacriticInsensitive() async throws {
        let model = await loadedModel(CountingVenueService(venues: Self.all))

        model.searchQuery = "CAFE ANEJO"
        await waitForDebounce(model)
        #expect(names(model) == ["Café Añejo Roasters"])
    }

    @Test func neighborhoodMatchesToo() async throws {
        let model = await loadedModel(CountingVenueService(venues: Self.all))

        model.searchQuery = "greenwich"
        await waitForDebounce(model)
        #expect(names(model) == ["Reading Room"])
    }

    @Test func prefixMatchesRankBeforeContainsMatches() async throws {
        let model = await loadedModel(CountingVenueService(venues: Self.all))

        model.searchQuery = "bottle"
        await waitForDebounce(model)
        #expect(names(model) == ["Bottle House", "Blue Bottle"])
    }

    /// Regression guard for the bd#226 CI investigation: typed narrowing
    /// (#225's `activeSearchText`/debounce) must keep working both with NO
    /// filter active and while a filter (#226's `hasActiveFilter`/
    /// `confirmedVenues`) is active — `venues` and the honest confirmed/
    /// unknown split built on top of it must never regress back to the full,
    /// unnarrowed list in either path.
    @Test func searchNarrowsWithAndWithoutAnActiveFilter() async {
        let model = await loadedModel(CountingVenueService(venues: Self.all))

        // No filter active: search alone narrows `venues`.
        model.searchQuery = "bottle"
        model.submitSearch()
        #expect(!model.hasActiveFilter)
        #expect(names(model) == ["Bottle House", "Blue Bottle"])

        // A filter becomes active on top of a settled search: every fixture
        // has fast Wi-Fi, so both narrowed venues stay `.confirmed` — the
        // narrowing must still hold, not widen back to all four.
        model.minWifi = .fast
        #expect(model.hasActiveFilter)
        #expect(names(model) == ["Bottle House", "Blue Bottle"])
        #expect(model.confirmedVenues.map(\.name) == ["Bottle House", "Blue Bottle"])
        #expect(model.unknownVenues.isEmpty)
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

    /// bd#200: honors `query.search` the way the real engine's `q` param
    /// does — a case/diacritic-insensitive contains over name or
    /// neighborhood — so the citywide-search union logic under test has a
    /// realistic "server" to union `venues` against. Every other query
    /// field stays ignored, unchanged from before.
    func fetchVenues(_ query: VenueQuery) async throws -> [Venue] {
        fetchCount += 1
        guard let search = query.search, !search.isEmpty else { return venues }
        let needle = search.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return venues.filter { venue in
            let name = venue.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let neighborhood = venue.neighborhood.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return name.contains(needle) || neighborhood.contains(needle)
        }
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
