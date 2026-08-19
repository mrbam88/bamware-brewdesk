import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum VenueAPIError: Error, LocalizedError, Sendable {
    case badURL
    case invalidResponse
    case http(statusCode: Int)
    case decoding
    case unsupportedSpeedTest

    public var errorDescription: String? {
        switch self {
        case .badURL:
            "The venue request could not be created."
        case .invalidResponse:
            "The venue service returned an invalid response."
        case .http(let statusCode):
            "The venue service returned HTTP \(statusCode)."
        case .decoding:
            "The venue service returned data in an unexpected format."
        case .unsupportedSpeedTest:
            "Speed observations require a remote HTTPS venue service."
        }
    }
}

public protocol VenueListing: Sendable {
    func fetchVenues(_ query: VenueQuery) async throws -> [Venue]
}

public protocol VenueDetailServing: Sendable {
    func fetchVenue(id: String) async throws -> Venue
}

public protocol VenueMeasuring: Sendable {
    var supportsSpeedTest: Bool { get }
    func submitSpeedTest(venueId: String, mbpsDown: Double) async throws -> Venue
    func measureDownloadMbps(samples: Int) async throws -> Double
}

/// Async client for the bamware-venue-engine master API.
/// The iOS Simulator reaches `http://localhost:3000` on the host Mac directly.
/// The app target permits local HTTP networking in its Debug configuration.
public struct VenueAPI: VenueListing, VenueDetailServing, VenueMeasuring, Sendable {
    public static var defaultBaseURL: URL {
        #if DEBUG
        URL(string: "http://localhost:3000")!
        #else
        URL(string: "https://venuekit-ashen.vercel.app")!
        #endif
    }

    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = VenueAPI.defaultBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public var supportsSpeedTest: Bool {
        baseURL.scheme == "https" && baseURL.host != "localhost" && baseURL.host != "127.0.0.1"
    }

    public func fetchVenues(_ query: VenueQuery) async throws -> [Venue] {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/v1/venues"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = query.urlQueryItems
        guard let url = comps.url else { throw VenueAPIError.badURL }
        return try await get(VenueListResponse.self, from: url).venues
    }

    public func fetchVenue(id: String) async throws -> Venue {
        try await get(
            VenueDetailResponse.self,
            from: baseURL.appendingPathComponent("/v1/venues/\(id)")
        ).venue
    }

    public func fetchNeighborhoods() async throws -> [NeighborhoodsResponse.Hood] {
        try await get(NeighborhoodsResponse.self, from: baseURL.appendingPathComponent("/v1/neighborhoods")).neighborhoods
    }

    /// The data flywheel: submit a measured download speed; the engine updates
    /// the wifi claim (source=speed_test, confidence 0.9) and rescores.
    @discardableResult
    public func submitSpeedTest(venueId: String, mbpsDown: Double) async throws -> Venue {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/observations"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(
            ObservationRequest(venueId: venueId, kind: "speed_test", mbpsDown: mbpsDown)
        )
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp)
        return try JSONDecoder().decode(ObservationResponse.self, from: data).venue
    }

    /// Rough downstream estimate from uncached JSON fetches against a remote
    /// HTTPS service. A dedicated known-size payload should replace this before
    /// production measurement claims are enabled.
    public func measureDownloadMbps(samples: Int = 3) async throws -> Double {
        guard supportsSpeedTest else { throw VenueAPIError.unsupportedSpeedTest }
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/v1/venues"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            .init(name: "limit", value: "200"),
            .init(name: "_speed_test_nonce", value: UUID().uuidString)
        ]
        guard let url = comps.url else { throw VenueAPIError.badURL }

        var totalBytes = 0.0
        var totalSeconds = 0.0
        for _ in 0..<max(samples, 1) {
            let start = Date()
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, resp) = try await session.data(for: request)
            try Self.check(resp)
            totalSeconds += Date().timeIntervalSince(start)
            totalBytes += Double(data.count)
        }
        let mbps = (totalBytes * 8 / 1_000_000) / max(totalSeconds, 0.001)
        return min((mbps * 10).rounded() / 10, 500)
    }

    private func get<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, resp) = try await session.data(from: url)
        try Self.check(resp)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch is DecodingError {
            throw VenueAPIError.decoding
        }
    }

    private static func check(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else { throw VenueAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw VenueAPIError.http(statusCode: http.statusCode)
        }
    }
}
