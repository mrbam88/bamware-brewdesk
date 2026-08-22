// Community capture — venue-engine photo intake client (brewdesk#71).
// Debug-only per the capture policy (Guideline 2.3.1) — see
// CaptureUploadContract.swift.
//
// PROVISIONAL WIRE SHAPE: venue-engine#21 (intake + AI auto-vet +
// moderation queue) is being built in parallel with this client. The issue
// pins the semantics — "intake endpoint links uploaded photo → venue",
// auto-vet, human approval queue, approved photos appearing in
// `/v1/venues/:id/photos` — but not the exact path/body. This client
// follows the engine's established REST grammar
// (`/v1/venues/:id/observations`, `/v1/venues/:id/photos`):
//
//   POST /v1/venues/{venueID}/photos/intake   (Bearer, JSON)
//   { uploadId, url, contentType, kind, contributorName? }
//
// If ve#21 lands differently, `VenueIntakeLinking` is the seam: only this
// file (and its wire tests) changes; the chain, the flow, and the flow's
// tests do not.
#if DEBUG
import Foundation

public struct VenueIntakeAPI: VenueIntakeLinking, Sendable {
    public let baseURL: URL
    private let session: URLSession

    /// Defaults to the venue engine BrewDesk already talks to
    /// (`VenueAPI.defaultBaseURL` — localhost:3000 in Debug).
    public init(baseURL: URL = VenueAPI.defaultBaseURL, session: URLSession = VenueAPI.defaultSession) {
        self.baseURL = baseURL
        self.session = session
    }

    public func linkUploadedPhoto(_ link: CapturePhotoIntakeLink, accessToken: String) async throws {
        var request = URLRequest(
            url: baseURL.appendingPathComponent("/v1/venues/\(link.venueID)/photos/intake")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            IntakeBody(
                uploadId: link.uploadID,
                url: link.url,
                contentType: link.contentType,
                kind: link.kind,
                contributorName: link.contributorName
            )
        )
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UploadRailError.invalidResponse }
        switch http.statusCode {
        case 200...299: return
        case 401: throw UploadRailError.sessionExpired
        case 404: throw UploadRailError.uploadExpired
        default: throw UploadRailError.http(statusCode: http.statusCode)
        }
    }

    private struct IntakeBody: Encodable {
        let uploadId, url, contentType, kind: String
        let contributorName: String?
    }
}
#endif
