// Community capture — real upload rail contract (brewdesk#71).
// Debug-only like every other capture file (Guideline 2.3.1): the capture
// entry itself never ships in a store build, so its networking must not
// ship either. When capture graduates from the Debug gate, lifting this
// guard is the deliberate, reviewed step.
//
// The chain a submission travels (dating-service PR #19 + venue-engine#21):
//   signed-in check (BrewDeskKit) → presign → S3 PUT → confirm → intake link
// Each stage sits behind its own protocol so tests can mock any transport
// and UI tests never touch the network.
#if DEBUG
import Foundation

/// Errors surfaced by the upload rail. `LocalizedError` so the capture flow
/// UI can show the specific problem next to its Retry button.
public enum UploadRailError: Error, Equatable, LocalizedError {
    /// Client-side pre-check: community submissions require an account
    /// (brewdesk#48); the rail is JWT-authenticated end to end.
    case signInRequired
    /// 401 — the access token was rejected (expired ≤15-min token; v1 has
    /// no auto-refresh, re-login is the documented recovery).
    case sessionExpired
    /// 403 — the asserted tenant did not match the JWT tenant.
    case tenantMismatch
    /// 400 — the service refused the upload (content type, size, unknown
    /// tenant). Carries the server's message; Debug-only feature, so
    /// surfacing it verbatim is a feature, not a leak.
    case rejected(String)
    /// 404 on confirm — the upload record or S3 object is gone (presigned
    /// URLs live 5 minutes; a slow shoot can outlive one).
    case uploadExpired
    /// 409 — this uploadId was already confirmed. Retries re-presign fresh
    /// ids, so seeing this means a duplicated confirm, not a duplicate photo.
    case alreadyConfirmed
    /// The S3 PUT itself failed with a non-2xx status.
    case storageUploadFailed(statusCode: Int)
    case invalidResponse
    case http(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .signInRequired:
            "Sign in from the Account screen to share photos, then try again."
        case .sessionExpired:
            "Your session expired. Sign in again, then try again."
        case .tenantMismatch:
            "This account can't submit BrewDesk photos."
        case .rejected(let reason):
            "The upload service refused a photo: \(reason)"
        case .uploadExpired:
            "The upload took too long and expired. Try again."
        case .alreadyConfirmed:
            "These photos were already submitted."
        case .storageUploadFailed:
            "Couldn't upload a photo. Check your connection and try again."
        case .invalidResponse:
            "Unexpected response from the upload service."
        case .http(let statusCode):
            "Upload service error (HTTP \(statusCode))."
        }
    }
}

/// `POST /v2/uploads/presign` response (dating-service `uploadService.ts`
/// `PresignResult`, pinned by fixture-recorded tests).
public struct PresignedUpload: Decodable, Equatable, Sendable {
    public let uploadId: String
    /// Presigned S3 PUT URL, valid 5 minutes.
    public let uploadUrl: String
    /// The eventual public URL — nothing is served from it until moderation
    /// approves the record.
    public let url: String
    public let status: String
    /// Tenant size limit (10 MB for `bamware-brewdesk`); checked client-side
    /// before the PUT so an oversized shot fails fast, and enforced
    /// server-side via HeadObject on confirm.
    public let maxBytes: Int

    public init(uploadId: String, uploadUrl: String, url: String, status: String, maxBytes: Int) {
        self.uploadId = uploadId
        self.uploadUrl = uploadUrl
        self.url = url
        self.status = status
        self.maxBytes = maxBytes
    }
}

/// `POST /v2/uploads/confirm` response — the subset of the service's
/// `UploadRecord` the client uses (additive server fields never break us).
/// For tenant `bamware-brewdesk`, `status` lands `"pending"` (moderation
/// default) — the photo is NOT public yet.
public struct ConfirmedUpload: Decodable, Equatable, Sendable {
    public let uploadId: String
    public let url: String
    public let contentType: String
    public let status: String
    public let sizeBytes: Int?

    public init(uploadId: String, url: String, contentType: String, status: String, sizeBytes: Int?) {
        self.uploadId = uploadId
        self.url = url
        self.contentType = contentType
        self.status = status
        self.sizeBytes = sizeBytes
    }
}

/// One uploadable shot: the guided flow's slot id (`CaptureShotKind.rawValue`)
/// plus JPEG bytes. Skipped slots never reach the rail — VenueKit stays free
/// of UIKit and of the flow's types.
public struct CaptureUploadShot: Equatable, Sendable {
    public let kind: String
    public let jpegData: Data

    public init(kind: String, jpegData: Data) {
        self.kind = kind
        self.jpegData = jpegData
    }
}

/// What the venue-engine intake needs to tie a confirmed upload to a venue
/// (venue-engine#21): the upload's identity, which guided slot it answers,
/// and the contributor byline (brewdesk#49 renders it once approved).
public struct CapturePhotoIntakeLink: Equatable, Sendable {
    public let venueID: String
    public let uploadID: String
    public let url: String
    public let contentType: String
    public let kind: String
    public let contributorName: String?

    public init(
        venueID: String,
        uploadID: String,
        url: String,
        contentType: String,
        kind: String,
        contributorName: String?
    ) {
        self.venueID = venueID
        self.uploadID = uploadID
        self.url = url
        self.contentType = contentType
        self.kind = kind
        self.contributorName = contributorName
    }
}

/// dating-service v2 upload rail. Live: `UploadRailAPI`. Tests: mocks.
public protocol UploadRailServing: Sendable {
    func presign(contentType: String, accessToken: String) async throws -> PresignedUpload
    func confirm(uploadID: String, accessToken: String) async throws -> ConfirmedUpload
}

/// The S3 PUT to a presigned URL. Live: `S3ObjectUploader`. Tests: mocks.
public protocol ObjectStorageUploading: Sendable {
    func putObject(_ data: Data, to url: URL, contentType: String) async throws
}

/// venue-engine intake (venue-engine#21, built in parallel with this client).
/// Live: `VenueIntakeAPI`. This protocol is the isolation seam: if ve#21
/// lands with a different wire shape, only the live client moves.
public protocol VenueIntakeLinking: Sendable {
    func linkUploadedPhoto(_ link: CapturePhotoIntakeLink, accessToken: String) async throws
}

/// Orchestrates the full rail for one submission, shot by shot, strictly in
/// order: presign → PUT → confirm → intake link. Fails fast on the first
/// error — the capture flow keeps the photos and offers Retry, and a retry
/// re-runs the whole submission with fresh presigns (uploadIds are
/// single-use; abandoned `awaiting-upload` records are the service's
/// cleanup concern, not client state).
public struct CaptureUploadChain: Sendable {
    /// The flow compresses every shot with `jpegData(compressionQuality:)`,
    /// so the rail always declares JPEG (in the brewdesk tenant allowlist).
    public static let contentType = "image/jpeg"

    private let rail: any UploadRailServing
    private let storage: any ObjectStorageUploading
    private let intake: any VenueIntakeLinking

    public init(
        rail: any UploadRailServing,
        storage: any ObjectStorageUploading,
        intake: any VenueIntakeLinking
    ) {
        self.rail = rail
        self.storage = storage
        self.intake = intake
    }

    public func submit(
        venueID: String,
        shots: [CaptureUploadShot],
        contributorName: String?,
        accessToken: String
    ) async throws {
        for shot in shots {
            let presigned = try await rail.presign(
                contentType: Self.contentType,
                accessToken: accessToken
            )
            guard let putURL = URL(string: presigned.uploadUrl) else {
                throw UploadRailError.invalidResponse
            }
            // Fail before the PUT, not after uploading megabytes the
            // service will HeadObject-reject and delete on confirm.
            guard shot.jpegData.count <= presigned.maxBytes else {
                throw UploadRailError.rejected(
                    "Photo is larger than the \(presigned.maxBytes)-byte tenant limit."
                )
            }
            try await storage.putObject(shot.jpegData, to: putURL, contentType: Self.contentType)
            let confirmed = try await rail.confirm(
                uploadID: presigned.uploadId,
                accessToken: accessToken
            )
            try await intake.linkUploadedPhoto(
                CapturePhotoIntakeLink(
                    venueID: venueID,
                    uploadID: confirmed.uploadId,
                    url: confirmed.url,
                    contentType: confirmed.contentType,
                    kind: shot.kind,
                    contributorName: contributorName
                ),
                accessToken: accessToken
            )
        }
    }
}
#endif
