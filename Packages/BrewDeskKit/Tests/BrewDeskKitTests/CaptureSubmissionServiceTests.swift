// LiveCaptureSubmissionService + resolver tests (brewdesk#71). All
// transports mocked — the signed-in gate, the flow→rail payload mapping,
// and launch-argument service resolution, with zero network. Debug-only
// like the rest of capture (Guideline 2.3.1).
#if DEBUG
import Foundation
import Testing
import UIKit
import VenueKit

@testable import BrewDeskKit

/// Chain-facing spies. The chain itself is proven in VenueKitTests
/// (CaptureUploadChainTests); here they only record what the live service
/// feeds into the chain.
private final class RailSpy: UploadRailServing, @unchecked Sendable {
    private let lock = NSLock()
    private var _presigns: [(contentType: String, token: String)] = []
    var presigns: [(contentType: String, token: String)] { lock.withLock { _presigns } }

    func presign(contentType: String, accessToken: String) async throws -> PresignedUpload {
        let count = lock.withLock {
            _presigns.append((contentType, accessToken))
            return _presigns.count
        }
        return PresignedUpload(
            uploadId: "upload-\(count)",
            uploadUrl: "https://s3.test/put/upload-\(count)",
            url: "https://photos.test/upload-\(count).jpg",
            status: "awaiting-upload",
            maxBytes: 10_485_760
        )
    }

    func confirm(uploadID: String, accessToken: String) async throws -> ConfirmedUpload {
        ConfirmedUpload(
            uploadId: uploadID,
            url: "https://photos.test/\(uploadID).jpg",
            contentType: "image/jpeg",
            status: "pending",
            sizeBytes: nil
        )
    }
}

private final class StorageSpy: ObjectStorageUploading, @unchecked Sendable {
    private let lock = NSLock()
    private var _putSizes: [Int] = []
    var putSizes: [Int] { lock.withLock { _putSizes } }

    func putObject(_ data: Data, to url: URL, contentType: String) async throws {
        lock.withLock { _putSizes.append(data.count) }
    }
}

private final class IntakeSpy: VenueIntakeLinking, @unchecked Sendable {
    private let lock = NSLock()
    private var _links: [CapturePhotoIntakeLink] = []
    var links: [CapturePhotoIntakeLink] { lock.withLock { _links } }

    func linkUploadedPhoto(_ link: CapturePhotoIntakeLink, accessToken: String) async throws {
        lock.withLock { _links.append(link) }
    }
}

@Suite @MainActor struct CaptureSubmissionServiceTests {
    private let rail = RailSpy()
    private let storage = StorageSpy()
    private let intake = IntakeSpy()

    private func makeService(session: AuthSession?) -> LiveCaptureSubmissionService {
        LiveCaptureSubmissionService(
            sessionStore: AccountSessionStore(persistence: InMemorySessionStore(session: session)),
            chain: CaptureUploadChain(rail: rail, storage: storage, intake: intake)
        )
    }

    private static let session = AuthSession(
        accessToken: "jwt-live",
        refreshToken: "refresh",
        user: AuthUser(
            userId: "user-1", email: "ada@bamware.com", name: "Ada L.",
            tenantId: BrewDeskTenant.id
        )
    )

    private func submission(venueID: String = "fixture-roasters") -> CaptureSubmission {
        let jpeg = CaptureSamplePhoto.image(for: .roomFromDoor).jpegData(compressionQuality: 0.7)!
        return CaptureSubmission(
            venueID: venueID,
            shots: [
                CaptureSubmission.Shot(kind: .roomFromDoor, imageData: jpeg),
                CaptureSubmission.Shot(kind: .seatingArea, imageData: nil),  // skipped
                CaptureSubmission.Shot(kind: .outlets, imageData: jpeg),
            ]
        )
    }

    @Test func signedOutThrowsSignInRequiredBeforeAnyNetwork() async {
        let service = makeService(session: nil)
        await #expect(throws: UploadRailError.signInRequired) {
            try await service.submit(submission())
        }
        #expect(rail.presigns.isEmpty, "The gate fires before the rail is touched")
        #expect(storage.putSizes.isEmpty)
        #expect(intake.links.isEmpty)
    }

    @Test func signedInSubmissionUploadsOnlyRealShotsWithSessionIdentity() async throws {
        try await makeService(session: Self.session).submit(submission())

        #expect(rail.presigns.count == 2, "Two photos, one skip — skips never reach the rail")
        #expect(rail.presigns.allSatisfy { $0.token == "jwt-live" }, "The #48 session JWT rides every call")
        #expect(rail.presigns.allSatisfy { $0.contentType == "image/jpeg" })
        #expect(storage.putSizes.count == 2)

        #expect(intake.links.map(\.kind) == ["room-from-door", "outlets"])
        #expect(intake.links.map(\.venueID) == ["fixture-roasters", "fixture-roasters"])
        #expect(
            intake.links.allSatisfy { $0.contributorName == "Ada L." },
            "The byline (brewdesk#49) travels from the signed-in user to intake"
        )
    }

    // MARK: - Resolver

    @Test func normalLaunchResolvesTheLiveRail() {
        let resolved = CaptureSubmissionServiceResolver.resolve(
            environment: LaunchEnvironment(arguments: []),
            fallback: MockCaptureSubmissionService()
        )
        #expect(resolved is LiveCaptureSubmissionService)
    }

    @Test func scenarioLaunchKeepsTheInjectedMock() {
        let fallback = MockCaptureSubmissionService()
        let resolved = CaptureSubmissionServiceResolver.resolve(
            environment: LaunchEnvironment(arguments: ["-UITestScenario", "fixtureOK"]),
            fallback: fallback
        )
        #expect(resolved === fallback)
    }

    @Test func scenarioLaunchWithFailuresScriptsAFailingMock() {
        let resolved = CaptureSubmissionServiceResolver.resolve(
            environment: LaunchEnvironment(arguments: ["-UITestScenario", "fixtureOK", "-UITestCaptureFailures", "2"]),
            fallback: MockCaptureSubmissionService()
        )
        let mock = resolved as? MockCaptureSubmissionService
        #expect(mock?.failuresRemaining == 2)
    }

    @Test func malformedFailuresArgumentFallsBackToTheInjectedMock() {
        let fallback = MockCaptureSubmissionService()
        let resolved = CaptureSubmissionServiceResolver.resolve(
            environment: LaunchEnvironment(arguments: ["-UITestScenario", "fixtureOK", "-UITestCaptureFailures", "lots"]),
            fallback: fallback
        )
        #expect(resolved === fallback)
    }
}
#endif
