import Foundation
import Testing
@testable import BrewDeskKit
import VenueKit

/// Privacy-claim verifier (brewdesk#29), model layer: which coordinate
/// `VenuesModel` hands to the venue engine in each location state.
///
/// - Denied / not yet determined → the public Union Square anchor.
/// - Granted but outside NYC coverage (App Review in California) → the
///   device coordinate is rejected and the anchor is queried instead, so a
///   reviewer's location never leaves the device.
/// - Granted inside coverage → the device coordinate, full precision, to the
///   engine only (see PrivacyRequestAuditTests for the wire-level half).
@Suite @MainActor struct VenuesModelPrivacyTests {
    private let anchor = (lat: 40.7359, lng: -73.9911)
    private let cupertino = (lat: 37.3230, lng: -122.0322)
    private let empireState = (lat: 40.7484, lng: -73.9857)

    @Test func withoutLocationTheAnchorIsQueried() async {
        let log = QueryLog()
        let model = VenuesModel(api: log)
        #expect(model.request.query.lat == anchor.lat)
        #expect(model.request.query.lng == anchor.lng)

        await model.load(model.request)
        #expect(log.queries.count == 1)
        #expect(log.queries.last?.lat == anchor.lat)
        #expect(log.queries.last?.lng == anchor.lng)
    }

    @Test func outOfCoverageDeviceCoordinateIsNeverSent() async {
        let log = QueryLog()
        let model = VenuesModel(api: log)
        #expect(!model.updateCenterIfNeeded(lat: cupertino.lat, lng: cupertino.lng))
        #expect(model.isOutsideCoverage)

        await model.load(model.request)
        model.browseCoverageCenter()
        await model.load(model.request)

        #expect(!log.queries.isEmpty)
        for query in log.queries {
            #expect(query.lat == anchor.lat)
            #expect(query.lng == anchor.lng)
            #expect(query.lat != cupertino.lat)
            #expect(query.lng != cupertino.lng)
        }
    }

    @Test func inCoverageDeviceCoordinateIsTheOnlyOtherValue() async {
        let log = QueryLog()
        let model = VenuesModel(api: log)
        #expect(model.updateCenterIfNeeded(lat: empireState.lat, lng: empireState.lng))
        await model.load(model.request)

        #expect(log.queries.last?.lat == empireState.lat)
        #expect(log.queries.last?.lng == empireState.lng)

        // Browse NYC snaps straight back to the anchor — no lingering coordinate.
        model.browseCoverageCenter()
        #expect(model.request.query.lat == anchor.lat)
        #expect(model.request.query.lng == anchor.lng)
    }

    @Test func coverageAnchorIsUnionSquare() {
        #expect(VenuesModel.coverageCenterLat == anchor.lat)
        #expect(VenuesModel.coverageCenterLng == anchor.lng)
        #expect(VenuesModel.coverageRadiusM == 50_000)
    }
}

/// Records each query the model sends; returns no venues.
nonisolated private final class QueryLog: VenueListing, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [VenueQuery] = []

    var queries: [VenueQuery] { lock.withLock { stored } }

    func fetchVenues(_ query: VenueQuery) async throws -> [Venue] {
        lock.withLock { stored.append(query) }
        return []
    }
}
