import Foundation
import Testing
import VenueKit
@testable import BrewDeskKit

/// bd#223 — "the search field should remember recent search history."
/// `RecentSearchStore` is pure state + persistence (no view code), so this
/// exercises capacity, de-duplication/reordering, and the word-prefix
/// matching used to surface recents above live results while typing —
/// directly, with an in-memory fake persistence, no running `Map`.
struct RecentSearchStoreTests {

    /// Records writes so a test can assert the store actually persisted
    /// (not just held state in memory) and never wrote anything before the
    /// UI-test reset path explicitly asks it to.
    @MainActor
    final class FakePersistence: RecentSearchPersisting {
        var stored: [RecentSearchEntry] = []
        var saveCount = 0

        init(seed: [RecentSearchEntry] = []) { stored = seed }

        func loadEntries() -> [RecentSearchEntry] { stored }
        func saveEntries(_ entries: [RecentSearchEntry]) {
            stored = entries
            saveCount += 1
        }
    }

    private func venue(id: String, name: String, neighborhood: String = "Test", lat: Double = 40.7, lng: Double = -74.0) -> Venue {
        let observedAt = "2026-08-01T00:00:00Z"
        return Venue(
            id: id, name: name, lat: lat, lng: lng, address: nil, neighborhood: neighborhood,
            borough: "Manhattan", hoursRaw: nil, vertical: "cafe",
            attributes: VenueAttributes(
                wifi: Claim(value: "fast", mbpsRange: nil, source: "curated", confidence: 0.9, observedAt: observedAt),
                outlets: Claim(value: "some", source: "curated", confidence: 0.9, observedAt: observedAt),
                laptopPolicy: Claim(value: "unrestricted", source: "curated", confidence: 0.9, observedAt: observedAt),
                noise: Claim(value: "moderate", source: "agent", confidence: 0.6, observedAt: observedAt),
                seating: Claim(value: "some", source: "agent", confidence: 0.6, observedAt: observedAt)
            ),
            vibeTags: [], workScore: 50, lastVerified: nil, distanceM: nil
        )
    }

    // MARK: - Recording + ordering

    @MainActor
    @Test func recordingACafeSelectionPutsItFirst() {
        let store = RecentSearchStore(persistence: FakePersistence(), launchEnvironment: .production)
        store.recordSelection(of: venue(id: "a", name: "Fixture A"))
        store.recordSelection(of: venue(id: "b", name: "Fixture B"))
        #expect(store.entries.map(\.title) == ["Fixture B", "Fixture A"])
    }

    @MainActor
    @Test func recordingTheSameCafeAgainMovesItToTheTopInsteadOfDuplicating() {
        let store = RecentSearchStore(persistence: FakePersistence(), launchEnvironment: .production)
        store.recordSelection(of: venue(id: "a", name: "Fixture A"))
        store.recordSelection(of: venue(id: "b", name: "Fixture B"))
        store.recordSelection(of: venue(id: "a", name: "Fixture A"))
        #expect(store.entries.count == 2)
        #expect(store.entries.map(\.title) == ["Fixture A", "Fixture B"])
    }

    @MainActor
    @Test func recordingTheSameQueryCaseInsensitivelyDedupes() {
        let store = RecentSearchStore(persistence: FakePersistence(), launchEnvironment: .production)
        store.recordSubmittedQuery("sey")
        store.recordSubmittedQuery("greenwich")
        store.recordSubmittedQuery("SEY")
        #expect(store.entries.count == 2)
        #expect(store.entries.map(\.title) == ["SEY", "greenwich"])
    }

    @MainActor
    @Test func shortQueriesAreNeverRecorded() {
        let store = RecentSearchStore(persistence: FakePersistence(), launchEnvironment: .production)
        store.recordSubmittedQuery("s")
        store.recordSubmittedQuery(" ")
        store.recordSubmittedQuery("")
        #expect(store.entries.isEmpty)
    }

    @MainActor
    @Test func capacityStaysAtTenNewestFirst() {
        let store = RecentSearchStore(persistence: FakePersistence(), launchEnvironment: .production)
        for i in 0..<15 {
            store.recordSubmittedQuery("query\(i)")
        }
        #expect(store.entries.count == RecentSearchStore.capacity)
        #expect(store.entries.first?.title == "query14")
        #expect(store.entries.last?.title == "query5")
    }

    // MARK: - Removal

    @MainActor
    @Test func removeAtIndexPersists() {
        let persistence = FakePersistence()
        let store = RecentSearchStore(persistence: persistence, launchEnvironment: .production)
        store.recordSubmittedQuery("greenwich")
        store.recordSubmittedQuery("chelsea")
        store.remove(at: 0)
        #expect(store.entries.map(\.title) == ["greenwich"])
        #expect(persistence.stored.map(\.title) == ["greenwich"])
    }

    @MainActor
    @Test func clearEmptiesAndPersists() {
        let persistence = FakePersistence()
        let store = RecentSearchStore(persistence: persistence, launchEnvironment: .production)
        store.recordSubmittedQuery("greenwich")
        store.clear()
        #expect(store.entries.isEmpty)
        #expect(persistence.stored.isEmpty)
    }

    @MainActor
    @Test func removeGoneCafeRemovesAndSetsAMessage() {
        let store = RecentSearchStore(persistence: FakePersistence(), launchEnvironment: .production)
        store.recordSelection(of: venue(id: "gone", name: "Fixture Gone"))
        store.removeGoneCafe(id: "gone", name: "Fixture Gone")
        #expect(store.entries.isEmpty)
        #expect(store.lastRemovalReason == "Fixture Gone no longer exists")
        store.clearRemovalReason()
        #expect(store.lastRemovalReason == nil)
    }

    // MARK: - Persistence round trip

    @MainActor
    @Test func loadsFromPersistenceOnInitForANormalLaunch() {
        let persistence = FakePersistence(seed: [.query(text: "existing")])
        let store = RecentSearchStore(persistence: persistence, launchEnvironment: .production)
        #expect(store.entries.map(\.title) == ["existing"])
    }

    // MARK: - UI-test reset path (bd#223)

    @MainActor
    @Test func aUITestRunNeverInheritsAPreviousRunsPersistedRecents() {
        let persistence = FakePersistence(seed: [.query(text: "stale from a previous run")])
        let env = LaunchEnvironment(arguments: ["-UITestSkipGates"])
        let store = RecentSearchStore(persistence: persistence, launchEnvironment: env)
        #expect(store.entries.isEmpty)
        #expect(persistence.stored.isEmpty, "must overwrite the stale persisted value, not just ignore it in memory")
    }

    @MainActor
    @Test func aUITestRunSeedsFromTheLaunchArgumentWhenProvided() {
        let seedJSON = #"[{"kind":"cafe","id":"sey","name":"SEY Coffee","neighborhood":"Bushwick","lat":40.70,"lng":-73.93}]"#
        let persistence = FakePersistence(seed: [.query(text: "stale")])
        let env = LaunchEnvironment(arguments: ["-UITestSkipGates", "-brewdesk.recent-searches-seed", seedJSON])
        let store = RecentSearchStore(persistence: persistence, launchEnvironment: env)
        #expect(store.entries.map(\.title) == ["SEY Coffee"])
        #expect(store.entries.first?.cafeID == "sey")
    }

    // MARK: - Word-prefix matching (surfaced above live results while typing)

    @MainActor
    @Test func matchingFindsAWordPrefixHitAmongRecents() {
        let store = RecentSearchStore(persistence: FakePersistence(), launchEnvironment: .production)
        store.recordSelection(of: venue(id: "sey", name: "SEY Coffee"))
        store.recordSelection(of: venue(id: "jersey", name: "Jersey City Library"))
        let matches = store.matching(prefix: "sey")
        #expect(matches.map(\.title) == ["SEY Coffee"])
    }

    @MainActor
    @Test func matchingExcludesCafesAlreadyAmongLiveResults() {
        let store = RecentSearchStore(persistence: FakePersistence(), launchEnvironment: .production)
        store.recordSelection(of: venue(id: "sey", name: "SEY Coffee"))
        let matches = store.matching(prefix: "sey", excludingCafeIDs: ["sey"])
        #expect(matches.isEmpty)
    }

    @MainActor
    @Test func matchingCapsAtTheRequestedLimit() {
        let store = RecentSearchStore(persistence: FakePersistence(), launchEnvironment: .production)
        for i in 0..<5 {
            store.recordSubmittedQuery("sey\(i)")
        }
        #expect(store.matching(prefix: "sey", limit: 3).count == 3)
    }

    @MainActor
    @Test func matchingReturnsNothingForABlankPrefix() {
        let store = RecentSearchStore(persistence: FakePersistence(), launchEnvironment: .production)
        store.recordSubmittedQuery("greenwich")
        #expect(store.matching(prefix: "  ").isEmpty)
    }

    // MARK: - Codable round trip (the actual UserDefaults JSON shape)

    @MainActor
    @Test func cafeAndQueryEntriesRoundTripThroughJSON() throws {
        let entries: [RecentSearchEntry] = [
            .cafe(id: "sey", name: "SEY Coffee", neighborhood: "Bushwick", lat: 40.70, lng: -73.93),
            .query(text: "greenwich")
        ]
        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([RecentSearchEntry].self, from: data)
        #expect(decoded == entries)
    }
}
