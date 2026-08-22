import Foundation
import Testing
@testable import VenueKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Answers every request with one canned photos payload: the Google fixture
/// photo plus a community photo by "Ada L." (the engine shape the live
/// `/v1/venues/:id/photos` route serves once community photos ship).
/// Deliberately separate from `RecordingURLProtocol` — see
/// `liveAPIFiltersBlockedContributors`.
final class PhotoStubURLProtocol: URLProtocol {
    static let photosJSON = Data("""
    {"photos":[
      {"url":"https://lh3.googleusercontent.com/p/AF1QipTestPhoto=s1600-w1600",
       "attribution":"A Reviewer",
       "attributionUri":"https://maps.google.com/maps/contrib/123",
       "widthPx":1600,"heightPx":1200},
      {"url":"/v1/venues/fixture-roasters/photos/1/media",
       "contributorName":"Ada L.","widthPx":1200,"heightPx":900}
    ]}
    """.utf8)

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PhotoStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.photosJSON)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

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

    /// The live half of the same seam (brewdesk#66): `VenueAPI.fetchPhotos`
    /// filters through the block store exactly like `ScenarioVenueService`,
    /// so blocking hides a contributor's photos on the next real fetch too.
    ///
    /// Uses a private stub loader, NOT `RecordingURLProtocol`: the privacy
    /// audit suite asserts exact request counts on that recorder's shared
    /// array, and suites run in parallel — this test must not write into it.
    @Test func liveAPIFiltersBlockedContributors() async throws {
        let store = ContributorBlockStore(defaults: nil)
        let api = VenueAPI(
            baseURL: URL(string: "https://venuekit-ashen.vercel.app")!,
            session: PhotoStubURLProtocol.makeSession(),
            blockStore: store
        )

        let before = try await api.fetchPhotos(venueId: "fixture-roasters")
        #expect(before.count == 2)
        #expect(before.contains { $0.communityByline == "Ada L." })

        store.block("Ada L.")
        let after = try await api.fetchPhotos(venueId: "fixture-roasters")
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
