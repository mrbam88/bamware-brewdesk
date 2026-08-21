import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Test-only URL loading system plug-in that records every request a
/// `URLSession` issues and answers it from canned engine fixtures. Install it
/// through `RecordingURLProtocol.makeSession()` and hand that session to
/// `VenueAPI(baseURL:session:)`; nothing reaches the network.
///
/// Never registered globally (`URLProtocol.registerClass`) — it only sees the
/// traffic of sessions built by `makeSession()`, so it cannot disturb other
/// suites sharing the same test host.
final class RecordingURLProtocol: URLProtocol {
    struct Recorded: Sendable {
        let method: String
        let url: URL
        let body: Data?

        var host: String? { url.host }
        var path: String { url.path }
        var queryItems: [URLQueryItem] {
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        }
        var queryNames: [String] { queryItems.map(\.name) }
        func queryValue(_ name: String) -> String? {
            queryItems.first { $0.name == name }?.value ?? nil
        }
        /// Top-level JSON keys of the body, if the body is a JSON object.
        var bodyKeys: Set<String> {
            guard let body,
                  let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            else { return [] }
            return Set(object.keys)
        }
        /// True when `needle` appears anywhere in the absolute URL or body.
        func contains(_ needle: String) -> Bool {
            if url.absoluteString.contains(needle) { return true }
            guard let body, let text = String(data: body, encoding: .utf8) else { return false }
            return text.contains(needle)
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [Recorded] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        recorded = []
    }

    static var requests: [Recorded] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    /// An ephemeral session whose only loader is this protocol.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? Self.drain(request.httpBodyStream)
        let entry = Recorded(
            method: request.httpMethod ?? "GET",
            url: request.url!,
            body: body
        )
        Self.lock.lock()
        Self.recorded.append(entry)
        Self.lock.unlock()

        let (status, data) = EngineFixtures.respond(to: entry)
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

/// Canned venue-engine responses keyed by path. Mirrors the engine contract
/// (bamware-venue-engine src/app.ts) closely enough for VenueAPI to decode.
enum EngineFixtures {
    /// What the production engine hands back for photos: a keyless Google
    /// photo URI the client loads directly (src/places.ts). Third-party host,
    /// no coordinates, no identifiers — the audit asserts exactly that.
    static let googlePhotoURL = "https://lh3.googleusercontent.com/p/AF1QipTestPhoto=s1600-w1600"

    static func venuesJSON() -> Data {
        let url = Bundle.module.url(forResource: "venues", withExtension: "json")!
        return try! Data(contentsOf: url)
    }

    private static func firstVenueJSON() -> Any {
        let object = try! JSONSerialization.jsonObject(with: venuesJSON()) as! [String: Any]
        return (object["venues"] as! [Any])[0]
    }

    private static func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    static func respond(to request: RecordingURLProtocol.Recorded) -> (Int, Data) {
        let path = request.path
        switch (request.method, path) {
        case ("GET", "/v1/health"):
            return (200, json(["ok": true, "venueCount": 2180, "seededAt": "2026-08-03T21:45:13.039Z"]))
        case ("GET", "/v1/venues"):
            return (200, venuesJSON())
        case ("GET", "/v1/neighborhoods"):
            return (200, json(["neighborhoods": [["name": "Williamsburg", "borough": "Brooklyn", "count": 12]]]))
        case ("POST", "/v1/observations"):
            return (201, json(["venue": firstVenueJSON()]))
        case ("POST", _) where path.hasPrefix("/v1/venues/") && path.hasSuffix("/observations"):
            // Structured community observation (brewdesk#47). Mirrors the
            // engine contract (venue-engine PR #26): 401 whenever
            // submittedBy is missing, empty, or whitespace; otherwise 201
            // with the stored record + rescored venue.
            guard let body = request.body,
                  let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let submitter = object["submittedBy"] as? String,
                  !submitter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return (401, json(["error": "missing_submitter"]))
            }
            return (201, json([
                "observation": [
                    "kind": "community",
                    "source": "community",
                    "submittedBy": submitter,
                ],
                "venue": firstVenueJSON(),
            ]))
        case ("GET", _) where path.hasPrefix("/v1/venues/") && path.hasSuffix("/photos"):
            return (200, json(["photos": [[
                "url": googlePhotoURL,
                "attribution": "A Reviewer",
                "attributionUri": "https://maps.google.com/maps/contrib/123",
                "widthPx": 1600, "heightPx": 1200,
            ]]]))
        case ("GET", _) where path.hasPrefix("/v1/venues/"):
            return (200, json(["venue": firstVenueJSON(), "observations": []]))
        default:
            return (404, json(["error": "not_found"]))
        }
    }
}
