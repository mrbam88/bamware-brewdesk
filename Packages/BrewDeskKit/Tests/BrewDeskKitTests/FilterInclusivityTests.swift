import Foundation
import Testing
@testable import BrewDeskKit
import VenueKit

/// brewdesk#77 — selecting all filters must never empty the list for the
/// wrong reason. Semantics under test:
///
/// - Within a category, a selection that admits every option ("all selected",
///   i.e. the weakest floor) is identical to no filter at all — including for
///   venues whose value is unknown.
/// - A constraining floor excludes only venues KNOWN to sit below it; an
///   unknown/absent value is not evidence against a venue.
/// - Categories combine with AND, which is safe once the two rules above hold.
/// - Filtering happens over the already-loaded list: changing a filter
///   triggers no network request.
///
/// `EngineLikeVenueService` mirrors the venue engine's `store.ts` predicate
/// (unknown fails every floor) so these tests reproduce the live zero-cafes
/// bug faithfully before the fix, and prove the app no longer delegates
/// category filtering to that predicate after it.
///
/// brewdesk#222: `matches`/`apply` (what every test below still asserts on)
/// are unchanged — a venue this suite calls a "match" is still exactly what
/// `venues` includes. What changed is what's BEHIND that boolean: it's now
/// `VenueFilter.classify(_:) != .excluded`, and several of the "matches"
/// cases here are specifically `.unknown`, not `.confirmed` — `allUnknown`
/// in particular is `.unknown` in every test it survives a filter in (its
/// every attribute is the literal string `"unknown"`, or absent for
/// seating). `FilterClassificationTests` is the new suite that asserts the
/// three-way outcome directly; `matchesClassifyAgreesWithTheLegacyBooleanOnEveryFixture`
/// below is the seam proving the two stay in lockstep for these exact
/// fixtures.
@Suite @MainActor struct FilterInclusivityTests {
    // The typical live venue: strong known claims, NO seating claim (99/100
    // live venues carry none — the exact shape the bug empties out).
    private static let knownGood = filterFixtureVenue(
        id: "known-good", wifi: "fast", outlets: "plenty", seating: nil,
        laptopPolicy: "unrestricted", venueType: "cafe"
    )
    private static let mid = filterFixtureVenue(
        id: "mid", wifi: "ok", outlets: "some", seating: "some",
        laptopPolicy: "unrestricted", venueType: "cafe"
    )
    private static let knownWeak = filterFixtureVenue(
        id: "known-weak", wifi: "slow", outlets: "scarce", seating: "scarce",
        laptopPolicy: "discouraged", venueType: "library"
    )
    private static let allUnknown = filterFixtureVenue(
        id: "all-unknown", wifi: "unknown", outlets: "unknown", seating: nil,
        laptopPolicy: "unknown", venueType: nil
    )
    private static let all = [knownGood, mid, knownWeak, allUnknown]

    private func loadedModel(_ api: EngineLikeVenueService) async -> VenuesModel {
        let model = VenuesModel(api: api)
        await model.load(model.request)
        return model
    }

    private func ids(_ model: VenuesModel) -> [String] {
        model.venues.map(\.id)
    }

    // MARK: - The reported bug (issue title)

    @Test func selectingEveryFilterOptionStillShowsCafes() async {
        let model = await loadedModel(EngineLikeVenueService(venues: Self.all))

        model.laptopFriendlyOnly = true
        model.minWifi = .fast
        model.minOutlets = .plenty
        model.minSeating = .plenty
        await model.load(model.request)

        // known-good is fast + plenty + laptop-unrestricted; its seating is
        // merely unobserved. It must survive "everything selected", as must
        // the venue nothing is known about — unknown is not evidence against.
        #expect(ids(model) == ["known-good", "all-unknown"])
    }

    // MARK: - All-selected == no-filter, per category

    @Test func allInclusiveWifiSelectionEqualsNoFilter() async {
        let model = await loadedModel(EngineLikeVenueService(venues: Self.all))
        #expect(ids(model) == Self.all.map(\.id))

        model.minWifi = .slow   // admits slow/ok/fast — every option
        await model.load(model.request)
        #expect(ids(model) == Self.all.map(\.id))
    }

    @Test func allInclusiveOutletsSelectionEqualsNoFilter() async {
        let model = await loadedModel(EngineLikeVenueService(venues: Self.all))

        model.minOutlets = .scarce
        await model.load(model.request)
        #expect(ids(model) == Self.all.map(\.id))
    }

    @Test func allInclusiveSeatingSelectionEqualsNoFilter() async {
        let model = await loadedModel(EngineLikeVenueService(venues: Self.all))

        model.minSeating = .scarce
        await model.load(model.request)
        #expect(ids(model) == Self.all.map(\.id))
    }

    @Test func combinationOfAllInclusiveSelectionsEqualsNoFilter() async {
        let model = await loadedModel(EngineLikeVenueService(venues: Self.all))

        model.minWifi = .slow
        model.minOutlets = .scarce
        model.minSeating = .scarce
        await model.load(model.request)
        #expect(ids(model) == Self.all.map(\.id))
    }

    // MARK: - Constraining floors: known-below excluded, unknown kept

    @Test func wifiFloorExcludesOnlyVenuesKnownBelowIt() async {
        let model = await loadedModel(EngineLikeVenueService(venues: Self.all))

        model.minWifi = .ok
        #expect(ids(model) == ["known-good", "mid", "all-unknown"])
    }

    @Test func seatingFloorExcludesOnlyVenuesKnownBelowIt() async {
        let model = await loadedModel(EngineLikeVenueService(venues: Self.all))

        model.minSeating = .some
        #expect(ids(model) == ["known-good", "mid", "all-unknown"])
    }

    @Test func outletsFloorExcludesOnlyVenuesKnownBelowIt() async {
        let model = await loadedModel(EngineLikeVenueService(venues: Self.all))

        model.minOutlets = .plenty
        #expect(ids(model) == ["known-good", "all-unknown"])
    }

    @Test func laptopFriendlyExcludesOnlyKnownHostileVenues() async {
        let model = await loadedModel(EngineLikeVenueService(venues: Self.all))

        model.laptopFriendlyOnly = true
        #expect(ids(model) == ["known-good", "mid", "all-unknown"])
    }

    /// brewdesk#240: `all-unknown` (no `venueType` on the wire) is never
    /// excluded by a narrowed type selection — it's honestly `.unknown`,
    /// same as every other dimension's absent/unrecognized value — so it
    /// keeps appearing under EVERY type selection, not just "cafe" (the old,
    /// now-removed `?? "cafe"` default).
    @Test func venueTypeFilterNeverDefaultsUntypedVenuesToCafe() async {
        let model = await loadedModel(EngineLikeVenueService(venues: Self.all))

        model.selectedVenueTypes = [.cafe]
        #expect(ids(model) == ["known-good", "mid", "all-unknown"])

        model.selectedVenueTypes = [.library]
        #expect(ids(model) == ["known-weak", "all-unknown"])
    }

    // MARK: - Combination coverage across categories (AND of constraints)

    @Test func crossCategoryCombinationsANDOverKnownValues() async {
        let model = await loadedModel(EngineLikeVenueService(venues: Self.all))

        model.minWifi = .ok
        model.minOutlets = .some
        #expect(ids(model) == ["known-good", "mid", "all-unknown"])

        model.minWifi = .fast
        #expect(ids(model) == ["known-good", "all-unknown"])

        model.laptopFriendlyOnly = true
        model.minSeating = .some
        model.selectedVenueTypes = [.cafe]
        #expect(ids(model) == ["known-good", "all-unknown"])
    }

    // MARK: - No network per filter change

    @Test func changingFiltersRequeriesNothing() async {
        let api = EngineLikeVenueService(venues: Self.all)
        let model = await loadedModel(api)
        let loadsAfterFirstFetch = await api.fetchCount

        model.minWifi = .fast
        model.minOutlets = .plenty
        model.laptopFriendlyOnly = true
        _ = model.venues
        // The request the UI observes must not change — filters are local.
        #expect(model.request.query.wifiMinimum == nil)
        #expect(model.request.query.outletMinimum == nil)
        #expect(model.request.query.seatingMinimum == nil)
        #expect(model.request.query.venueType == nil)
        #expect(model.request.query.laptopFriendlyOnly == false)
        #expect(await api.fetchCount == loadsAfterFirstFetch)
    }

    // MARK: - Filtered-to-zero is still possible, for honest reasons

    @Test func impossibleKnownValueCombinationIsStillEmpty() async {
        let model = await loadedModel(EngineLikeVenueService(venues: [Self.knownWeak]))

        model.minWifi = .fast
        #expect(model.venues.isEmpty)   // known-slow really is below the floor
    }

    // MARK: - brewdesk#222: `classify` justification

    /// The seam this suite's class doc comment promises: for every fixture
    /// venue here, `matches` still agrees exactly with `classify(_:) !=
    /// .excluded` — the pre-#222 binary contract every test above asserts
    /// on is a strict derivation of the new three-way one, not a parallel
    /// implementation that could drift from it.
    @Test func matchesClassifyAgreesWithTheLegacyBooleanOnEveryFixture() {
        let filter = VenueFilter(
            laptopFriendlyOnly: true, minWifi: .fast, minOutlets: .plenty,
            minSeating: .plenty, selectedVenueTypes: [.cafe]
        )
        for venue in Self.all {
            #expect(filter.matches(venue) == (filter.classify(venue) != .excluded), "disagreement for \(venue.id)")
        }
    }

    /// `allUnknown` — every constrained attribute literally `"unknown"` (or
    /// absent, for seating) — is the fixture the confirmed/unknown split
    /// exists for: it "matches" every filter above because nothing about it
    /// is KNOWN to fail, but it was never actually CONFIRMED. brewdesk#222
    /// moves it from an undifferentiated "match" to `.unknown` — it now
    /// renders in the shelf's "Might match · details unknown" section and
    /// as a map speck, never presented as an equal to `known-good`, which
    /// really does confirm every constraint.
    @Test func allUnknownIsClassifiedUnknownNotConfirmedUnderEveryConstrainingFilter() {
        let laptop = VenueFilter(laptopFriendlyOnly: true)
        #expect(laptop.classify(Self.allUnknown) == .unknown)

        let wifi = VenueFilter(minWifi: .ok)
        #expect(wifi.classify(Self.allUnknown) == .unknown)

        let outlets = VenueFilter(minOutlets: .plenty)
        #expect(outlets.classify(Self.allUnknown) == .unknown)

        let seating = VenueFilter(minSeating: .some)
        #expect(seating.classify(Self.allUnknown) == .unknown)

        // `known-good` has the same "matches" outcome as `allUnknown` under
        // every filter above (see `selectingEveryFilterOptionStillShowsCafes`),
        // but it's genuinely `.confirmed` — the distinction `matches` alone
        // could never express.
        #expect(wifi.classify(Self.knownGood) == .confirmed)
    }
}

// MARK: - Fixtures

/// Mirrors `bamware-venue-engine/src/store.ts` `query()`: every category ANDs,
/// and an unknown/absent value fails any floor (`!tier → continue`). Kept
/// engine-faithful so the pre-fix tests reproduce the live bug exactly.
private actor EngineLikeVenueService: VenueListing {
    let venues: [Venue]
    private(set) var fetchCount = 0

    init(venues: [Venue]) {
        self.venues = venues
    }

    func fetchVenues(_ query: VenueQuery) async throws -> [Venue] {
        fetchCount += 1
        let wifiOrder = ["slow": 1, "ok": 2, "fast": 3]
        let amountOrder = ["scarce": 1, "some": 2, "plenty": 3]
        return venues.filter { venue in
            if let minimum = query.wifiMinimum {
                guard let tier = wifiOrder[venue.attributes.wifi.value],
                      tier >= wifiOrder[minimum.rawValue]! else { return false }
            }
            if let minimum = query.outletMinimum {
                guard let tier = amountOrder[venue.attributes.outlets.value],
                      tier >= amountOrder[minimum.rawValue]! else { return false }
            }
            if let minimum = query.seatingMinimum {
                guard let tier = amountOrder[venue.attributes.seating?.value ?? "unknown"],
                      tier >= amountOrder[minimum.rawValue]! else { return false }
            }
            if let type = query.venueType, (venue.venueType ?? "cafe") != type.rawValue {
                return false
            }
            if query.laptopFriendlyOnly, venue.attributes.laptopPolicy.value == "discouraged" {
                return false
            }
            return true
        }
    }
}

private func filterFixtureVenue(
    id: String,
    wifi: String,
    outlets: String,
    seating: String?,
    laptopPolicy: String,
    venueType: String?
) -> Venue {
    let observedAt = "2026-08-01T00:00:00Z"
    func claim(_ value: String) -> Claim {
        Claim(value: value, source: "curated", confidence: 0.8, observedAt: observedAt)
    }
    return Venue(
        id: id,
        name: id,
        lat: 40.7359,
        lng: -73.9911,
        address: nil,
        neighborhood: "Union Square",
        borough: "Manhattan",
        hoursRaw: nil,
        vertical: "cafe",
        attributes: VenueAttributes(
            wifi: claim(wifi),
            outlets: claim(outlets),
            laptopPolicy: claim(laptopPolicy),
            noise: claim("moderate"),
            seating: seating.map(claim)
        ),
        vibeTags: [],
        workScore: 70,
        lastVerified: nil,
        distanceM: nil,
        venueType: venueType
    )
}
