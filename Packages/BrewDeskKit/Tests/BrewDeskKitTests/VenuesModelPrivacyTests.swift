import Foundation
import Testing
@testable import BrewDeskKit
import VenueKit

/// Privacy-claim verifier (brewdesk#29), model layer: which coordinate
/// `VenuesModel` hands to the venue engine in each location state.
///
/// - Denied / not yet determined → the public Union Square anchor.
/// - Granted, anywhere → the device coordinate, full precision, to the
///   engine only (see PrivacyRequestAuditTests for the wire-level half).
///   bd#108 removed the >50km-from-NYC rejection this suite used to pin —
///   the app now always queries the real viewport it was given, so a
///   reviewer's location DOES reach the engine once granted; it is still
///   never sent anywhere else, never stored, and never sent at all without
///   an explicit grant (see docs/PRIVACY-AUDIT.md).
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

    @Test func aFarDeviceCoordinateIsSentLikeAnyOther() async {
        let log = QueryLog()
        let model = VenuesModel(api: log)
        #expect(model.updateCenterIfNeeded(lat: cupertino.lat, lng: cupertino.lng))

        await model.load(model.request)
        #expect(log.queries.last?.lat == cupertino.lat)
        #expect(log.queries.last?.lng == cupertino.lng)
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
