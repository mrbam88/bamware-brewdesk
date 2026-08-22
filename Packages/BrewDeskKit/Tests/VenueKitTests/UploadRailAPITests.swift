// Upload rail wire-contract tests (brewdesk#71): UploadRailAPI,
// S3ObjectUploader, and VenueIntakeAPI pinned through a recording URL
// protocol — nothing reaches the network, $0 spend. Response fixtures are
// recorded from the dating-service v2 sources (PR #19: `uploadSchemas.ts`,
// `uploadService.ts` PresignResult, `uploadHandler.ts` error mapping).
//
// Own recording class (not `RecordingURLProtocol`) so this suite's static
// request log cannot race other suites — same isolation trick as
// `AuthRecordingProtocol`.
#if DEBUG
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing

@testable import VenueKit

final class UploadRecordingProtocol: URLProtocol {
    struct Recorded: Sendable {
        let method: String
        let url: URL
        let body: Data?
        let headers: [String: String]

        var path: String { url.path }
        var bodyObject: [String: Any]? {
            guard let body else { return nil }
            return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [Recorded] = []
    /// Status + JSON body served for the next requests, keyed by path
    /// suffix; unmatched requests get 404.
    nonisolated(unsafe) private static var responses: [(pathSuffix: String, status: Int, body: Data)] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        recorded = []
        responses = []
    }

    static func respond(pathSuffix: String, status: Int, json: String) {
        lock.lock(); defer { lock.unlock() }
        responses.append((pathSuffix, status, Data(json.utf8)))
    }

    static var requests: [Recorded] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UploadRecordingProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? Self.drain(request.httpBodyStream)
        let entry = Recorded(
            method: request.httpMethod ?? "GET",
            url: request.url!,
            body: body,
            headers: request.allHTTPHeaderFields ?? [:]
        )
        Self.lock.lock()
        Self.recorded.append(entry)
        let match = Self.responses.first { entry.url.path.hasSuffix($0.pathSuffix) }
        Self.lock.unlock()

        let (status, data) = match.map { ($0.status, $0.body) } ?? (404, Data("{\"error\":\"not_found\"}".utf8))
        let response = HTTPURLResponse(
            url: entry.url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func drain(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

@Suite(.serialized) struct UploadRailAPITests {
    private let base = URL(string: "https://uploads.test")!

    /// Fixture recorded from `uploadService.ts` `PresignResult` for tenant
    /// `bamware-brewdesk` (10 MB limit, `uploads/` key prefix).
    private static let presignFixture = """
        {"uploadId":"9c5b7f3a-1d2e-4f60-8a9b-0c1d2e3f4a5b",
         "uploadUrl":"https://bamware-dev-photos.s3.us-east-1.amazonaws.com/uploads/bamware-brewdesk/user-1/9c5b7f3a-1d2e-4f60-8a9b-0c1d2e3f4a5b.jpg?X-Amz-Signature=sig",
         "url":"https://bamware-dev-photos.s3.us-east-1.amazonaws.com/uploads/bamware-brewdesk/user-1/9c5b7f3a-1d2e-4f60-8a9b-0c1d2e3f4a5b.jpg",
         "status":"awaiting-upload","maxBytes":10485760}
        """

    /// Fixture recorded from `uploadSchemas.ts` `UploadRecordSchema` after
    /// confirm — BrewDesk's moderation default is `pending` (PR #19):
    /// nothing is public until approved. Extra server keys (tenantId,
    /// userId, key, timestamps) prove additive fields never break decoding.
    private static let confirmFixture = """
        {"uploadId":"9c5b7f3a-1d2e-4f60-8a9b-0c1d2e3f4a5b",
         "tenantId":"bamware-brewdesk","userId":"user-1",
         "key":"uploads/bamware-brewdesk/user-1/9c5b7f3a-1d2e-4f60-8a9b-0c1d2e3f4a5b.jpg",
         "url":"https://bamware-dev-photos.s3.us-east-1.amazonaws.com/uploads/bamware-brewdesk/user-1/9c5b7f3a-1d2e-4f60-8a9b-0c1d2e3f4a5b.jpg",
         "contentType":"image/jpeg","sizeBytes":204800,"status":"pending",
         "createdAt":"2026-08-21T00:00:00.000Z","updatedAt":"2026-08-21T00:01:00.000Z"}
        """

    init() {
        UploadRecordingProtocol.reset()
    }

    private func makeAPI() -> UploadRailAPI {
        UploadRailAPI(baseURL: base, session: UploadRecordingProtocol.makeSession())
    }

    // MARK: - Presign

    @Test func presignSendsTenantAssertionAndBearerAndDecodes() async throws {
        UploadRecordingProtocol.respond(
            pathSuffix: "/v2/uploads/presign", status: 200, json: Self.presignFixture
        )
        let presigned = try await makeAPI().presign(contentType: "image/jpeg", accessToken: "jwt-abc")

        let request = try #require(UploadRecordingProtocol.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/v2/uploads/presign")
        #expect(request.headers["Authorization"] == "Bearer jwt-abc")
        #expect(request.bodyObject?["tenantId"] as? String == "bamware-brewdesk")
        #expect(request.bodyObject?["contentType"] as? String == "image/jpeg")

        #expect(presigned.uploadId == "9c5b7f3a-1d2e-4f60-8a9b-0c1d2e3f4a5b")
        #expect(presigned.uploadUrl.contains("X-Amz-Signature"))
        #expect(presigned.status == "awaiting-upload")
        #expect(presigned.maxBytes == 10_485_760)
    }

    @Test func presign401MapsToSessionExpired() async {
        UploadRecordingProtocol.respond(
            pathSuffix: "/v2/uploads/presign", status: 401,
            json: #"{"error":"Invalid or expired token"}"#
        )
        await #expect(throws: UploadRailError.sessionExpired) {
            _ = try await makeAPI().presign(contentType: "image/jpeg", accessToken: "stale")
        }
    }

    @Test func presign403MapsToTenantMismatch() async {
        UploadRecordingProtocol.respond(
            pathSuffix: "/v2/uploads/presign", status: 403,
            json: #"{"error":"tenantId does not match caller"}"#
        )
        await #expect(throws: UploadRailError.tenantMismatch) {
            _ = try await makeAPI().presign(contentType: "image/jpeg", accessToken: "jwt-abc")
        }
    }

    @Test func presign400CarriesTheServerReason() async {
        UploadRecordingProtocol.respond(
            pathSuffix: "/v2/uploads/presign", status: 400,
            json: #"{"error":"Content type not allowed for tenant bamware-brewdesk: image/gif"}"#
        )
        await #expect(
            throws: UploadRailError.rejected(
                "Content type not allowed for tenant bamware-brewdesk: image/gif")
        ) {
            _ = try await makeAPI().presign(contentType: "image/gif", accessToken: "jwt-abc")
        }
    }

    // MARK: - Confirm

    @Test func confirmSendsUploadIdAndDecodesModerationPendingRecord() async throws {
        UploadRecordingProtocol.respond(
            pathSuffix: "/v2/uploads/confirm", status: 200, json: Self.confirmFixture
        )
        let confirmed = try await makeAPI().confirm(
            uploadID: "9c5b7f3a-1d2e-4f60-8a9b-0c1d2e3f4a5b", accessToken: "jwt-abc"
        )

        let request = try #require(UploadRecordingProtocol.requests.first)
        #expect(request.path == "/v2/uploads/confirm")
        #expect(request.headers["Authorization"] == "Bearer jwt-abc")
        #expect(request.bodyObject?["uploadId"] as? String == "9c5b7f3a-1d2e-4f60-8a9b-0c1d2e3f4a5b")
        #expect(request.bodyObject?["tenantId"] as? String == "bamware-brewdesk")

        #expect(
            confirmed.status == "pending",
            "BrewDesk's tenant moderation default — never public before approval"
        )
        #expect(confirmed.contentType == "image/jpeg")
        #expect(confirmed.sizeBytes == 204_800)
    }

    @Test func confirm404MapsToUploadExpired() async {
        UploadRecordingProtocol.respond(
            pathSuffix: "/v2/uploads/confirm", status: 404,
            json: #"{"error":"Object not found in storage"}"#
        )
        await #expect(throws: UploadRailError.uploadExpired) {
            _ = try await makeAPI().confirm(uploadID: "gone", accessToken: "jwt-abc")
        }
    }

    @Test func confirm409MapsToAlreadyConfirmed() async {
        UploadRecordingProtocol.respond(
            pathSuffix: "/v2/uploads/confirm", status: 409,
            json: #"{"error":"Upload already confirmed"}"#
        )
        await #expect(throws: UploadRailError.alreadyConfirmed) {
            _ = try await makeAPI().confirm(uploadID: "dup", accessToken: "jwt-abc")
        }
    }

    // MARK: - S3 PUT

    @Test func s3PutSendsRawBytesWithSignedURLAndContentType() async throws {
        UploadRecordingProtocol.respond(pathSuffix: "/put/object.jpg", status: 200, json: "{}")
        let bytes = Data(repeating: 7, count: 321)
        let url = URL(string: "https://bucket.s3.test/put/object.jpg?X-Amz-Signature=sig")!
        try await S3ObjectUploader(session: UploadRecordingProtocol.makeSession())
            .putObject(bytes, to: url, contentType: "image/jpeg")

        let request = try #require(UploadRecordingProtocol.requests.first)
        #expect(request.method == "PUT")
        #expect(request.url == url, "The presigned URL is used verbatim — the signature is the credential")
        #expect(request.headers["Content-Type"] == "image/jpeg")
        #expect(request.headers["Authorization"] == nil, "No bearer leaks to S3")
        #expect(request.body == bytes)
    }

    @Test func s3PutNon2xxMapsToStorageUploadFailed() async {
        UploadRecordingProtocol.respond(pathSuffix: "/put/object.jpg", status: 403, json: "{}")
        await #expect(throws: UploadRailError.storageUploadFailed(statusCode: 403)) {
            try await S3ObjectUploader(session: UploadRecordingProtocol.makeSession()).putObject(
                Data([1]),
                to: URL(string: "https://bucket.s3.test/put/object.jpg")!,
                contentType: "image/jpeg"
            )
        }
    }

    // MARK: - Venue-engine intake (provisional shape, ve#21 seam)

    @Test func intakeLinksUploadToVenueWithBearer() async throws {
        UploadRecordingProtocol.respond(
            pathSuffix: "/v1/venues/fixture-roasters/photos/intake", status: 201,
            json: #"{"ok":true,"status":"queued"}"#
        )
        try await VenueIntakeAPI(baseURL: base, session: UploadRecordingProtocol.makeSession())
            .linkUploadedPhoto(
                CapturePhotoIntakeLink(
                    venueID: "fixture-roasters",
                    uploadID: "9c5b7f3a-1d2e-4f60-8a9b-0c1d2e3f4a5b",
                    url: "https://photos.test/uploads/x.jpg",
                    contentType: "image/jpeg",
                    kind: "room-from-door",
                    contributorName: "Ada L."
                ),
                accessToken: "jwt-abc"
            )

        let request = try #require(UploadRecordingProtocol.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/v1/venues/fixture-roasters/photos/intake")
        #expect(request.headers["Authorization"] == "Bearer jwt-abc")
        #expect(request.bodyObject?["uploadId"] as? String == "9c5b7f3a-1d2e-4f60-8a9b-0c1d2e3f4a5b")
        #expect(request.bodyObject?["kind"] as? String == "room-from-door")
        #expect(request.bodyObject?["contributorName"] as? String == "Ada L.")
        #expect(request.bodyObject?["url"] as? String == "https://photos.test/uploads/x.jpg")
    }

    @Test func intake401MapsToSessionExpired() async {
        UploadRecordingProtocol.respond(
            pathSuffix: "/photos/intake", status: 401, json: #"{"error":"unauthorized"}"#
        )
        await #expect(throws: UploadRailError.sessionExpired) {
            try await VenueIntakeAPI(baseURL: base, session: UploadRecordingProtocol.makeSession())
                .linkUploadedPhoto(
                    CapturePhotoIntakeLink(
                        venueID: "v", uploadID: "u", url: "https://x.test/p.jpg",
                        contentType: "image/jpeg", kind: "outlets", contributorName: nil
                    ),
                    accessToken: "stale"
                )
        }
    }
}
#endif
