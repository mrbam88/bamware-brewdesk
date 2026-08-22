// Capture upload chain tests (brewdesk#71): mocked transports prove the
// end-to-end order — presign → S3 PUT → confirm → intake — plus fail-fast
// error surfacing at every stage. The chain (and everything capture)
// compiles only in Debug; the guard keeps a Release test build compiling
// to an empty file.
#if DEBUG
import Foundation
import Testing

@testable import VenueKit

/// One shared, lock-guarded event log across all three mocked transports —
/// asserting on a single ordered list is what proves the sequencing.
private final class ChainRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []
    private var presignCount = 0

    var events: [String] { lock.withLock { _events } }
    func record(_ event: String) { lock.withLock { _events.append(event) } }
    func nextUploadID() -> String { lock.withLock { presignCount += 1; return "upload-\(presignCount)" } }
}

private struct MockRail: UploadRailServing {
    let recorder: ChainRecorder
    var maxBytes = 10_485_760
    var presignError: UploadRailError?
    var confirmError: UploadRailError?

    func presign(contentType: String, accessToken: String) async throws -> PresignedUpload {
        recorder.record("presign \(contentType) token=\(accessToken)")
        if let presignError { throw presignError }
        let id = recorder.nextUploadID()
        return PresignedUpload(
            uploadId: id,
            uploadUrl: "https://s3.test/put/\(id)?X-Amz-Signature=sig",
            url: "https://photos.test/uploads/bamware-brewdesk/user-1/\(id).jpg",
            status: "awaiting-upload",
            maxBytes: maxBytes
        )
    }

    func confirm(uploadID: String, accessToken: String) async throws -> ConfirmedUpload {
        recorder.record("confirm \(uploadID) token=\(accessToken)")
        if let confirmError { throw confirmError }
        return ConfirmedUpload(
            uploadId: uploadID,
            url: "https://photos.test/uploads/bamware-brewdesk/user-1/\(uploadID).jpg",
            contentType: "image/jpeg",
            status: "pending",
            sizeBytes: 1_024
        )
    }
}

private struct MockStorage: ObjectStorageUploading {
    let recorder: ChainRecorder
    var error: UploadRailError?

    func putObject(_ data: Data, to url: URL, contentType: String) async throws {
        recorder.record("put \(url.path) \(data.count)b \(contentType)")
        if let error { throw error }
    }
}

private struct MockIntake: VenueIntakeLinking {
    let recorder: ChainRecorder
    var error: UploadRailError?

    func linkUploadedPhoto(_ link: CapturePhotoIntakeLink, accessToken: String) async throws {
        recorder.record(
            "intake \(link.venueID) \(link.kind) \(link.uploadID) by=\(link.contributorName ?? "nil") token=\(accessToken)"
        )
        if let error { throw error }
    }
}

@Suite struct CaptureUploadChainTests {
    private let recorder = ChainRecorder()

    private func chain(
        rail: ((inout MockRail) -> Void)? = nil,
        storage: ((inout MockStorage) -> Void)? = nil,
        intake: ((inout MockIntake) -> Void)? = nil
    ) -> CaptureUploadChain {
        var mockRail = MockRail(recorder: recorder)
        rail?(&mockRail)
        var mockStorage = MockStorage(recorder: recorder)
        storage?(&mockStorage)
        var mockIntake = MockIntake(recorder: recorder)
        intake?(&mockIntake)
        return CaptureUploadChain(rail: mockRail, storage: mockStorage, intake: mockIntake)
    }

    private let shots = [
        CaptureUploadShot(kind: "room-from-door", jpegData: Data(repeating: 1, count: 100)),
        CaptureUploadShot(kind: "outlets", jpegData: Data(repeating: 2, count: 50)),
    ]

    @Test func chainRunsPresignPutConfirmIntakeInOrderPerShot() async throws {
        try await chain().submit(
            venueID: "venue-1",
            shots: shots,
            contributorName: "Ada L.",
            submittedBy: "test-submitter",
            accessToken: "jwt-1"
        )
        #expect(recorder.events == [
            "presign image/jpeg token=jwt-1",
            "put /put/upload-1 100b image/jpeg",
            "confirm upload-1 token=jwt-1",
            "intake venue-1 room-from-door upload-1 by=Ada L. token=jwt-1",
            "presign image/jpeg token=jwt-1",
            "put /put/upload-2 50b image/jpeg",
            "confirm upload-2 token=jwt-1",
            "intake venue-1 outlets upload-2 by=Ada L. token=jwt-1",
        ])
    }

    @Test func presignFailureStopsBeforeAnyUpload() async {
        await #expect(throws: UploadRailError.sessionExpired) {
            try await chain(rail: { $0.presignError = .sessionExpired }).submit(
                venueID: "venue-1", shots: shots, contributorName: nil, submittedBy: "test-submitter", accessToken: "jwt-1"
            )
        }
        #expect(recorder.events == ["presign image/jpeg token=jwt-1"])
    }

    @Test func storageFailureSurfacesAndSkipsConfirmAndIntake() async {
        await #expect(throws: UploadRailError.storageUploadFailed(statusCode: 500)) {
            try await chain(storage: { $0.error = .storageUploadFailed(statusCode: 500) }).submit(
                venueID: "venue-1", shots: shots, contributorName: nil, submittedBy: "test-submitter", accessToken: "jwt-1"
            )
        }
        #expect(recorder.events == [
            "presign image/jpeg token=jwt-1",
            "put /put/upload-1 100b image/jpeg",
        ], "Fail fast: no confirm, no intake, no second shot")
    }

    @Test func confirmFailureSkipsIntake() async {
        await #expect(throws: UploadRailError.uploadExpired) {
            try await chain(rail: { $0.confirmError = .uploadExpired }).submit(
                venueID: "venue-1", shots: shots, contributorName: nil, submittedBy: "test-submitter", accessToken: "jwt-1"
            )
        }
        #expect(recorder.events.count == 3, "presign, put, failed confirm — nothing after")
        #expect(recorder.events.last == "confirm upload-1 token=jwt-1")
    }

    @Test func intakeFailureSurfacesAndStopsTheSecondShot() async {
        await #expect(throws: UploadRailError.http(statusCode: 500)) {
            try await chain(intake: { $0.error = .http(statusCode: 500) }).submit(
                venueID: "venue-1", shots: shots, contributorName: nil, submittedBy: "test-submitter", accessToken: "jwt-1"
            )
        }
        #expect(recorder.events.count == 4, "First shot's full chain ran; second never started")
    }

    @Test func oversizedShotFailsBeforeThePut() async {
        await #expect(throws: UploadRailError.self) {
            try await chain(rail: { $0.maxBytes = 10 }).submit(
                venueID: "venue-1", shots: shots, contributorName: nil, submittedBy: "test-submitter", accessToken: "jwt-1"
            )
        }
        #expect(
            recorder.events == ["presign image/jpeg token=jwt-1"],
            "The tenant-limit pre-check rejects before uploading a doomed object"
        )
    }

    @Test func noShotsMeansNoNetworkAtAll() async throws {
        try await chain().submit(
            venueID: "venue-1", shots: [], contributorName: nil, submittedBy: "test-submitter", accessToken: "jwt-1"
        )
        #expect(recorder.events.isEmpty, "An all-skipped submission touches nothing")
    }
}
#endif
