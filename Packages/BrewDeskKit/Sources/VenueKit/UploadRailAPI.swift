// Community capture — dating-service v2 upload rail client (brewdesk#71).
// Debug-only per the capture policy (Guideline 2.3.1) — see
// CaptureUploadContract.swift.
//
// Wire contract (dating-service PR #19, `uploadHandler.ts` /
// `uploadSchemas.ts` / `uploadService.ts`; BrewDesk is tenant
// `bamware-brewdesk`):
// - `POST /v2/uploads/presign` (Bearer) `{tenantId?, contentType}` → 200
//   `{uploadId, uploadUrl, url, status, maxBytes}`; 400 type/tenant
//   rejected, 401 bad token, 403 tenant mismatch.
// - `POST /v2/uploads/confirm` (Bearer) `{uploadId, tenantId?}` → 200
//   UploadRecord with `status: "pending"` for BrewDesk (moderation
//   default — nothing public until approved); 404 record/object gone,
//   409 already confirmed, 400 size/type verification failed.
// The JWT is authoritative for tenant; the body `tenantId` is sent as an
// explicit assertion (the PR's defense-in-depth option).
#if DEBUG
import Foundation

public struct UploadRailAPI: UploadRailServing, Sendable {
    /// The capture flow is Debug-only, so this client only ever talks to a
    /// local dating-service (`pnpm dev`, PORT=3002 per its .env.example —
    /// its JWT_SECRET must match bamware-auth-service's so #48 sessions
    /// verify here). When capture graduates from the Debug gate, add the
    /// deployed API Gateway URL the way `AuthAPI.defaultBaseURL` does.
    public static var defaultBaseURL: URL { URL(string: "http://localhost:3002")! }

    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = UploadRailAPI.defaultBaseURL, session: URLSession = VenueAPI.defaultSession) {
        self.baseURL = baseURL
        self.session = session
    }

    public func presign(contentType: String, accessToken: String) async throws -> PresignedUpload {
        try await post(
            "/v2/uploads/presign",
            body: PresignBody(tenantId: BrewDeskTenant.id, contentType: contentType),
            accessToken: accessToken
        )
    }

    public func confirm(uploadID: String, accessToken: String) async throws -> ConfirmedUpload {
        try await post(
            "/v2/uploads/confirm",
            body: ConfirmBody(uploadId: uploadID, tenantId: BrewDeskTenant.id),
            accessToken: accessToken
        )
    }

    // MARK: - Plumbing

    private struct PresignBody: Encodable {
        let tenantId, contentType: String
    }

    private struct ConfirmBody: Encodable {
        let uploadId, tenantId: String
    }

    private struct ErrorBody: Decodable {
        let error: String
    }

    private func post<Response: Decodable>(
        _ path: String,
        body: some Encodable,
        accessToken: String
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UploadRailError.invalidResponse }
        switch http.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw UploadRailError.invalidResponse
            }
        case 400:
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw UploadRailError.rejected(message ?? "The request was rejected.")
        case 401: throw UploadRailError.sessionExpired
        case 403: throw UploadRailError.tenantMismatch
        case 404: throw UploadRailError.uploadExpired
        case 409: throw UploadRailError.alreadyConfirmed
        default: throw UploadRailError.http(statusCode: http.statusCode)
        }
    }
}

/// The middle hop: raw JPEG bytes PUT straight to the presigned S3 URL.
/// No auth header — the signature in the URL is the credential; the
/// Content-Type must match what presign signed for.
public struct S3ObjectUploader: ObjectStorageUploading, Sendable {
    private let session: URLSession

    public init(session: URLSession = VenueAPI.defaultSession) {
        self.session = session
    }

    public func putObject(_ data: Data, to url: URL, contentType: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse else { throw UploadRailError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw UploadRailError.storageUploadFailed(statusCode: http.statusCode)
        }
    }
}
#endif
