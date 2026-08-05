import Testing
@testable import BamwareCafeKit
import VenueKit

@Suite @MainActor struct VenuesModelTests {
    @Test func staleFailureCannotReplaceNewerSuccess() async throws {
        let api = ControlledVenueService()
        let model = VenuesModel(api: api)

        let firstLoad = Task { await model.load() }
        await api.waitForRequest(key: "any")

        model.minWifi = "fast"
        let secondLoad = Task { await model.load() }
        await api.waitForRequest(key: "fast")

        await api.succeed(key: "fast")
        await secondLoad.value
        #expect(model.phase == .loaded)

        await api.fail(key: "any")
        await firstLoad.value
        #expect(model.phase == .loaded)
    }
}

private actor ControlledVenueService: VenueServing {
    private enum TestError: Error { case failed }
    private var requests: [String: CheckedContinuation<[Venue], any Error>] = [:]

    nonisolated var supportsSpeedTest: Bool { false }

    func fetchVenues(
        lat: Double?,
        lng: Double?,
        radiusM: Int,
        wifiMin: String?,
        outletsMin: String?,
        laptopFriendly: Bool,
        neighborhood: String?,
        query: String?,
        sort: String,
        limit: Int
    ) async throws -> [Venue] {
        let key = wifiMin ?? "any"
        return try await withCheckedThrowingContinuation { continuation in
            requests[key] = continuation
        }
    }

    func submitSpeedTest(venueId: String, mbpsDown: Double) async throws -> Venue {
        throw TestError.failed
    }

    func measureDownloadMbps(samples: Int) async throws -> Double {
        throw TestError.failed
    }

    func waitForRequest(key: String) async {
        while requests[key] == nil {
            await Task.yield()
        }
    }

    func succeed(key: String) {
        requests.removeValue(forKey: key)?.resume(returning: [])
    }

    func fail(key: String) {
        requests.removeValue(forKey: key)?.resume(throwing: TestError.failed)
    }
}
