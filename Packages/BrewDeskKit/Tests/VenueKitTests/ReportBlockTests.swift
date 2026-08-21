import Foundation
import Testing
@testable import VenueKit

/// Report + block seams (brewdesk#48, Apple 1.2).
@Suite struct ReportBlockTests {
    private func freshDefaults(_ name: String) -> UserDefaults {
        let suite = "report-block-tests-\(name)-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    // MARK: - ContributorBlockStore

    @Test func blockUnblockRoundTrip() {
        let store = ContributorBlockStore(defaults: nil)
        #expect(!store.isBlocked("Ada L."))

        store.block("  Ada L. ") // normalized
        #expect(store.isBlocked("Ada L."))
        #expect(store.blockedNames == ["Ada L."])

        store.unblock("Ada L.")
        #expect(!store.isBlocked("Ada L."))
        #expect(store.blockedNames.isEmpty)
    }

    @Test func blockedNamesPersistAcrossInstances() {
        let defaults = freshDefaults("persist")
        ContributorBlockStore(defaults: defaults).block("Ada L.")

        let reloaded = ContributorBlockStore(defaults: defaults)
        #expect(reloaded.isBlocked("Ada L."))
    }

    @Test func filteringDropsBlockedCommunityPhotosOnly() {
        let store = ContributorBlockStore(defaults: nil)
        store.block("Ada L.")

        let filtered = store.filteringBlocked(ScenarioVenueService.fixtureCommunityPhotos)
        // The Google-attributed photo (no byline) always passes through.
        #expect(filtered.count == 1)
        #expect(filtered[0].communityByline == nil)
        #expect(filtered[0].attribution == "Fixture Photographer")
    }

    @Test func emptyBlockListPassesEverythingThrough() {
        let store = ContributorBlockStore(defaults: nil)
        let photos = ScenarioVenueService.fixtureCommunityPhotos
        #expect(store.filteringBlocked(photos) == photos)
    }

    /// The end-to-end seam the block UI test rides: after blocking, the
    /// scenario service's photo fetch no longer serves the contributor.
    @Test func scenarioServiceFiltersBlockedContributors() async throws {
        let store = ContributorBlockStore(defaults: nil)
        let service = ScenarioVenueService(scenario: .communityPhotos, blockStore: store)

        let before = try await service.fetchPhotos(venueId: "fixture-roasters")
        #expect(before.count == 2)

        store.block("Ada L.")
        let after = try await service.fetchPhotos(venueId: "fixture-roasters")
        #expect(after.count == 1)
        #expect(after.allSatisfy { $0.communityByline == nil })
    }

    // MARK: - ReportSpool

    @Test func submitReportAppendsToSpool() async throws {
        let defaults = freshDefaults("spool")
        let spool = ReportSpool(defaults: defaults)

        let report = ContentReport(
            venueName: "Fixture Roasters",
            photoURL: "http://127.0.0.1:9/fixture-photo-community.jpg",
            contributorName: "Ada L.",
            reason: .inappropriate
        )
        try await spool.submitReport(report)
        try await spool.submitReport(
            ContentReport(venueName: "Fixture Roasters", photoURL: "u2", contributorName: nil, reason: .spam)
        )

        let pending = ReportSpool.pendingReports(defaults: defaults)
        #expect(pending.count == 2)
        #expect(pending[0] == report)
        #expect(pending[1].reason == .spam)
    }

    @Test func reportReasonWireValuesAreStable() {
        // Proposed engine contract (ReportContract.swift) — raw values are
        // wire values; renaming a case must break here first.
        #expect(ReportReason.allCases.map(\.rawValue) == ["inappropriate", "spam", "not_venue", "other"])
    }
}
