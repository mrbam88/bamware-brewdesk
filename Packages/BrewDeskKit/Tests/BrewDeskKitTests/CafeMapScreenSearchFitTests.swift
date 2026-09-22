import Foundation
import MapKit
import Testing
import VenueKit
@testable import BrewDeskKit

/// `CafeMapScreen.searchFitRegion` — the pure camera-fit geometry behind
/// brewdesk#158 ("search moves the map to the results"). Kept separate from
/// the gesture/debounce wiring in `CafeMapScreen` itself (untestable outside
/// a running `Map`), so this exercises only the deterministic math: one
/// result centers at neighborhood zoom, several fit their bounding box, and
/// the fit leaves room for the shelf card.
struct CafeMapScreenSearchFitTests {

    private func venue(id: String, name: String? = nil, lat: Double, lng: Double, neighborhood: String = "Test") -> Venue {
        let observedAt = "2026-08-01T00:00:00Z"
        return Venue(
            id: id,
            name: name ?? "Venue \(id)",
            lat: lat,
            lng: lng,
            address: nil,
            neighborhood: neighborhood,
            borough: "Manhattan",
            hoursRaw: nil,
            vertical: "cafe",
            attributes: VenueAttributes(
                wifi: Claim(value: "fast", mbpsRange: nil, source: "curated", confidence: 0.9, observedAt: observedAt),
                outlets: Claim(value: "some", source: "curated", confidence: 0.9, observedAt: observedAt),
                laptopPolicy: Claim(value: "unrestricted", source: "curated", confidence: 0.9, observedAt: observedAt),
                noise: Claim(value: "moderate", source: "agent", confidence: 0.6, observedAt: observedAt),
                seating: Claim(value: "some", source: "agent", confidence: 0.6, observedAt: observedAt)
            ),
            vibeTags: [],
            workScore: 50,
            lastVerified: nil,
            distanceM: nil
        )
    }

    @Test func emptyResultsFitNothing() {
        #expect(CafeMapScreen.searchFitRegion(for: [], mapHeight: 800, shelfClearance: 260) == nil)
    }

    @Test func singleResultCentersAtWalkingZoom() throws {
        let target = venue(id: "a", lat: 40.7359, lng: -73.9911)
        // No shelf/height info supplied ⇒ no vertical bias, so the fit is
        // exactly the walking-zoom span centered on the venue. bd#219: a
        // lone result is a selection target (Google-Maps-style pin drop),
        // not a neighborhood overview — this is the same span
        // `selectSearchResult`'s fly-to reuses this function to produce.
        let region = CafeMapScreen.searchFitRegion(for: [target], mapHeight: 0, shelfClearance: 0)
        let unwrapped = try #require(region)
        #expect(unwrapped.center.latitude == target.lat)
        #expect(unwrapped.center.longitude == target.lng)
        #expect(unwrapped.span.latitudeDelta == CafeMapScreen.walkingZoomSpan)
        #expect(unwrapped.span.longitudeDelta == CafeMapScreen.walkingZoomSpan)
        #expect(CafeMapScreen.walkingZoomSpan >= 0.008 && CafeMapScreen.walkingZoomSpan <= 0.010)
    }

    @Test func multipleResultsFitThePaddedBoundingBox() throws {
        let venues = [
            venue(id: "a", lat: 40.730, lng: -73.995),
            venue(id: "b", lat: 40.742, lng: -73.987)
        ]
        let region = CafeMapScreen.searchFitRegion(for: venues, mapHeight: 0, shelfClearance: 0)
        let unwrapped = try #require(region)

        // Center is the bounding-box midpoint (no shelf bias supplied).
        #expect(abs(unwrapped.center.latitude - 40.736) < 0.0001)
        #expect(abs(unwrapped.center.longitude - (-73.991)) < 0.0001)

        // Span comfortably exceeds the raw box (padding), and both results
        // fall well inside it.
        let rawLatSpan = 40.742 - 40.730
        let rawLngSpan = -73.987 - (-73.995)
        #expect(unwrapped.span.latitudeDelta > rawLatSpan)
        #expect(unwrapped.span.longitudeDelta > rawLngSpan)
        for v in venues {
            #expect(abs(v.lat - unwrapped.center.latitude) <= unwrapped.span.latitudeDelta / 2)
            #expect(abs(v.lng - unwrapped.center.longitude) <= unwrapped.span.longitudeDelta / 2)
        }
    }

    @Test func shelfClearanceShiftsTheFitNorthOfTheRawCenter() throws {
        let target = venue(id: "a", lat: 40.7359, lng: -73.9911)
        // A tall shelf relative to the map height reserves real room at the
        // bottom, so the fitted region's center must sit south of the
        // venue's true latitude — pushing the venue itself further north
        // on screen, clear of the card.
        let region = CafeMapScreen.searchFitRegion(for: [target], mapHeight: 800, shelfClearance: 300)
        let unwrapped = try #require(region)
        #expect(unwrapped.center.latitude < target.lat)
        // The venue must still fall within the fitted span.
        #expect(abs(target.lat - unwrapped.center.latitude) <= unwrapped.span.latitudeDelta / 2)
    }

    @Test func degenerateHeightFallsBackToNoBias() throws {
        let target = venue(id: "a", lat: 40.7359, lng: -73.9911)
        // Shelf clearance at or beyond the reported map height must not
        // divide by zero or invert the fit — falls back to no vertical bias.
        let region = CafeMapScreen.searchFitRegion(for: [target], mapHeight: 200, shelfClearance: 260)
        let unwrapped = try #require(region)
        #expect(unwrapped.center.latitude == target.lat)
    }

    // MARK: - Selection/submit guard (bd#219, revised bd#223)

    /// `selectSearchResult` itself needs a running `Map` (it drives
    /// `@State`/animation), so these exercise the pure guard it and
    /// `scheduleSearchFit` both consult — `shouldApplySearchFit` — directly.
    ///
    /// bd#223 (requirement 5 — "no camera moves while typing", replacing the
    /// brewdesk#158 tests that encoded the OLD "any non-empty, non-selected
    /// query" behavior): the guard now ALSO requires `query == submittedQuery`
    /// — nothing arms `submittedQuery` except an explicit keyboard Search/
    /// return (`CafeMapScreen.runSubmittedSearch`), so a query the user is
    /// still typing can never satisfy this guard regardless of how many
    /// results it matches. Every case below now passes a `submittedQuery`
    /// explicitly so the ORIGINAL brewdesk#158 intent (a settled search
    /// still moves the camera once armed) keeps its own coverage alongside
    /// the new "never while typing" cases.
    @Test func lateAnswerAfterASelectionProducesNoFitIntent() {
        // Once `searchSelectionQuery` (set by `selectSearchResult`) equals
        // the current query, a late server search answer — or the
        // selection's own surroundings reload changing `model.venues` again
        // — must never re-fit the camera for that same query, even if it was
        // also the last submitted one.
        #expect(!CafeMapScreen.shouldApplySearchFit(forQuery: "sey", selectionQuery: "sey", submittedQuery: "sey"))
    }

    @Test func aSubmittedQueryWithNoSelectionProducesAFitIntent() {
        #expect(CafeMapScreen.shouldApplySearchFit(forQuery: "sey", selectionQuery: nil, submittedQuery: "sey"))
        // A genuinely different, later query is never blocked by a stale
        // selection recorded for an earlier one.
        #expect(CafeMapScreen.shouldApplySearchFit(forQuery: "devocion", selectionQuery: "sey", submittedQuery: "devocion"))
    }

    @Test func blankQueryNeverProducesAFitIntent() {
        #expect(!CafeMapScreen.shouldApplySearchFit(forQuery: "   ", selectionQuery: nil, submittedQuery: "   "))
        #expect(!CafeMapScreen.shouldApplySearchFit(forQuery: "", selectionQuery: nil, submittedQuery: ""))
    }

    /// bd#223: the core of requirement 5 — a query matching plenty of
    /// results that the user is STILL TYPING (nothing has armed
    /// `submittedQuery` for it yet) must never produce a fit intent. This is
    /// the exact reproduction of Bilal's report: a one-letter query "T"
    /// matching cafés across the whole metro area while he was still typing.
    @Test func aQueryThatHasNotBeenSubmittedNeverProducesAFitIntentEvenIfNonEmpty() {
        #expect(!CafeMapScreen.shouldApplySearchFit(forQuery: "t", selectionQuery: nil, submittedQuery: nil))
        #expect(!CafeMapScreen.shouldApplySearchFit(forQuery: "t", selectionQuery: nil, submittedQuery: "some other, earlier submit"))
    }

    /// `selectSearchResult`'s fly-to reuses this exact function for its
    /// single-result path — proving the region it produces (one result,
    /// walking scale, biased north of the shelf) IS the fly-to intent, not
    /// a second, divergent calculation.
    @Test func selectionProducesExactlyOneFlyToIntentWithTheVisibleAreaOffset() throws {
        let target = venue(id: "far", lat: 40.6437, lng: -74.0787)
        let region = CafeMapScreen.searchFitRegion(for: [target], mapHeight: 800, shelfClearance: 260)
        let unwrapped = try #require(region)
        // Longitude is never shelf-shifted, so it stays exactly at the
        // walking-zoom span; latitude is inflated/shifted by the shelf bias
        // (asserted directly below), matching `shelfClearanceShiftsTheFitNorthOfTheRawCenter`.
        #expect(unwrapped.span.longitudeDelta == CafeMapScreen.walkingZoomSpan)
        #expect(unwrapped.span.latitudeDelta > CafeMapScreen.walkingZoomSpan, "shelf clearance widens the latitude span")
        #expect(unwrapped.center.latitude < target.lat, "must bias north, clear of the shelf")
        #expect(unwrapped.center.longitude == target.lng)
        #expect(abs(target.lat - unwrapped.center.latitude) <= unwrapped.span.latitudeDelta / 2)
    }

    /// bd#219 (supervisor revision): the ACTUAL fly-to region
    /// `selectSearchResult` computes, using its fixed 1:2 synthetic ratio
    /// standing in for a `.medium`-detent detail sheet (~half the screen).
    /// Exact numbers, not just directional assertions, since the UI test's
    /// own tolerance is now tight (150m) against this precise target.
    @Test func mediumSheetFlyToRegionMatchesTheDocumentedShift() throws {
        let target = venue(id: "far", lat: 40.6437, lng: -74.0787)
        let region = CafeMapScreen.searchFitRegion(
            for: [target],
            mapHeight: CafeMapScreen.mediumSheetSyntheticMapHeight,
            shelfClearance: CafeMapScreen.mediumSheetSyntheticObscuredHeight
        )
        let unwrapped = try #require(region)
        // obscuredFraction = 500/1000 = 0.5 ⇒ latitudeDelta = span/0.5 =
        // 2×span; shift = (0.5/2)×latitudeDelta = 0.25×latitudeDelta = a
        // quarter of the TOTAL region, i.e. half of the visible (top) half
        // — the venue lands dead-center in the visible portion.
        let expectedLatitudeDelta = CafeMapScreen.walkingZoomSpan / 0.5
        let expectedShift = 0.25 * expectedLatitudeDelta
        #expect(abs(unwrapped.span.latitudeDelta - expectedLatitudeDelta) < 1e-9)
        #expect(abs((target.lat - unwrapped.center.latitude) - expectedShift) < 1e-9)
        // In meters, for the PR's own documentation/tolerance discussion.
        let shiftMeters = expectedShift * 111_320
        #expect(shiftMeters > 400 && shiftMeters < 600, "expected roughly 500m, got \(shiftMeters)")
    }

    // MARK: - Word-prefix fit ranking (bd#219, supervisor revision)

    @Test func wordPrefixMatchWinsOverAMidWordSubstringHit() {
        // Reproduces Bilal's actual report: "sey" as a plain substring
        // matches BOTH "SEY Coffee" (a real word-prefix match) and "Jersey
        // City Free Public Library" (only because "sey" hides inside
        // "Jersey") — the fit must only ever consider the former.
        let seyCoffee = venue(id: "sey", name: "SEY Coffee", lat: 40.7054, lng: -73.9324)
        let jerseyLibrary = venue(id: "jersey", name: "Jersey City Free Public Library", lat: 40.7195, lng: -74.0480)
        let results = CafeMapScreen.wordPrefixRankedResults(for: "sey", in: [seyCoffee, jerseyLibrary])
        #expect(results.map(\.id) == ["sey"])
    }

    @Test func wordPrefixMatchChecksNeighborhoodToo() {
        let named = venue(id: "a", name: "Some Café", lat: 40.7, lng: -74.0)
        let inNeighborhood = venue(id: "b", name: "Other Café", lat: 40.71, lng: -74.01, neighborhood: "Seyhill")
        let results = CafeMapScreen.wordPrefixRankedResults(for: "sey", in: [named, inNeighborhood])
        #expect(results.map(\.id) == ["b"])
    }

    @Test func noWordPrefixMatchFallsBackToTopFive() {
        let venues = (0..<8).map { venue(id: "v\($0)", lat: 40.7 + Double($0) * 0.001, lng: -74.0) }
        // None of these venues' names ("Venue v0"…"Venue v7") or
        // neighborhoods ("Test") have a word starting with "zzz".
        let results = CafeMapScreen.wordPrefixRankedResults(for: "zzz", in: venues)
        #expect(results.count == 5)
        #expect(results.map(\.id) == venues.prefix(5).map(\.id))
    }

    @Test func blankQueryReturnsAllResultsUnfiltered() {
        let venues = [venue(id: "a", lat: 40.7, lng: -74.0), venue(id: "b", lat: 40.71, lng: -74.01)]
        #expect(CafeMapScreen.wordPrefixRankedResults(for: "  ", in: venues).count == 2)
    }
}
