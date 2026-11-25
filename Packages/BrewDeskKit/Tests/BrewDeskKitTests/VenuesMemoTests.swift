import Foundation
import Observation
import Testing
@testable import BrewDeskKit
import VenueKit

/// brewdesk#211 — `VenuesModel.venues` (and its confirmed/unknown halves)
/// are memoised. The memo must be invisible: the same answers as before,
/// recomputed whenever an input changes, and still observed by SwiftUI
/// even when a read was answered from the memo.
@Suite @MainActor struct VenuesMemoTests {
    private func loadedModel(_ scenario: ScenarioVenueService.Scenario) async -> VenuesModel {
        let model = VenuesModel(api: ScenarioVenueService(scenario: scenario))
        await model.load(model.request)
        return model
    }

    private func storage(_ venues: [Venue]) -> UnsafeRawPointer? {
        venues.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) }
    }

    @Test func repeatedReadsReturnTheSameArrayWithoutRecomputing() async {
        let model = await loadedModel(.manyVenues)
        let first = model.venues
        let second = model.venues
        #expect(first.count > 1_000)
        #expect(first == second)
        #expect(storage(first) == storage(second))
        #expect(storage(model.unknownVenues) == storage(model.unknownVenues))
    }

    @Test func aFilterChangeRecomputesAndUndoingItRestoresTheList() async {
        let model = await loadedModel(.filterHonesty)
        let unfiltered = model.venues
        #expect(!unfiltered.isEmpty)
        #expect(model.unknownVenues.isEmpty)

        model.minWifi = .fast
        let filtered = model.venues
        #expect(filtered.count < unfiltered.count)
        #expect(filtered == VenueOrdering.observedFirst(VenueFilter(
            laptopFriendlyOnly: false, minWifi: .fast, minOutlets: nil, minSeating: nil,
            selectedVenueTypes: Set(VenueTypeBadge.filterableCases)
        ).apply(to: unfiltered)))
        #expect(!model.unknownVenues.isEmpty)
        #expect(model.confirmedVenues.count + model.unknownVenues.count == filtered.count)

        model.minWifi = nil
        #expect(model.venues == unfiltered)
        #expect(model.unknownVenues.isEmpty)
        #expect(model.confirmedVenues.count == unfiltered.count)
    }

    @Test func aSearchNarrowsAndClearingRestores() async throws {
        let model = await loadedModel(.fixtureOK)
        let all = model.venues
        let name = try #require(all.first?.name)

        model.searchQuery = name
        model.submitSearch()
        let matches = model.venues
        #expect(matches.contains { $0.name == name })
        #expect(matches.count < all.count)

        model.clearSearch()
        #expect(model.venues == all)
    }

    @Test func aReadAnsweredFromTheMemoIsStillObserved() async {
        let model = await loadedModel(.filterHonesty)
        _ = model.venues    // fills the memo

        let changed = Flag()
        withObservationTracking {
            _ = model.venues    // answered from the memo
            _ = model.unknownVenues
        } onChange: {
            changed.set()
        }
        model.minWifi = .fast
        #expect(changed.value)
    }
}

private nonisolated final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var value: Bool { lock.withLock { raised } }
    func set() { lock.withLock { raised = true } }
}
