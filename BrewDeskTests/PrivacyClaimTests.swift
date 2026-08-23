import Foundation
import Testing
import VenueKit
import BrewDeskKit
@testable import BrewDesk

/// Privacy-claim verifier (brewdesk#29), host-app half. Runs inside the
/// BrewDesk.app test host, so under `-configuration Release` it inspects the
/// exact bundle that ships: the privacy manifest, the transport policy, and
/// the production endpoint.
@Suite @MainActor struct PrivacyClaimTests {
    private var manifest: [String: Any] {
        get throws {
            let url = try #require(
                Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
                "PrivacyInfo.xcprivacy must ship in the app bundle"
            )
            let data = try Data(contentsOf: url)
            let object = try PropertyListSerialization.propertyList(from: data, format: nil)
            return try #require(object as? [String: Any])
        }
    }

    @Test func privacyManifestDeclaresNoCollectionAndNoTracking() throws {
        let manifest = try manifest
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)

        let accessed = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        #expect(accessed.count == 1)
        #expect(accessed.first?["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults")
        #expect(accessed.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
    }

    @Test func locationIsOptionalWhenInUseOnly() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(info["NSLocationWhenInUseUsageDescription"] is String)
        #expect(info["NSLocationAlwaysAndWhenInUseUsageDescription"] == nil)
        #expect(info["NSLocationAlwaysUsageDescription"] == nil)
        let modes = info["UIBackgroundModes"] as? [String] ?? []
        #expect(!modes.contains("location"))
    }

    @Test func releaseBuildTalksHTTPSToTheProductionEngineOnly() {
        let base = VenueAPI.defaultBaseURL
        #if DEBUG
        #expect(base.host == "localhost")
        #else
        #expect(base.scheme == "https")
        #expect(base.host == "venuekit-ashen.vercel.app")
        // The Debug plist carries NSAllowsLocalNetworking; Release must not
        // carry any App Transport Security exception.
        #expect(Bundle.main.infoDictionary?["NSAppTransportSecurity"] == nil)
        #endif
    }

    /// The coordinate the app queries whenever no device location is in play
    /// (denied, undetermined, or outside NYC coverage). Pinned here because
    /// the go-live privacy position cites it by value.
    @Test func fallbackQueryTargetsUnionSquareNotTheDevice() {
        let model = VenuesModel(api: NoVenues())
        #expect(model.centerLat == 40.7359)
        #expect(model.centerLng == -73.9911)
    }
}

private struct NoVenues: VenueListing {
    func fetchVenues(_ query: VenueQuery) async throws -> [Venue] { [] }
}
