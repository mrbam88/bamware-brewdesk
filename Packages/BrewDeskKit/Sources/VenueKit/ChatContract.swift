// Wire contract for the engine's grounded café chat (bamware-brewdesk#247;
// server half: bamware-venue-engine#218). `POST /v1/chat`, bearer-authed,
// answers with a short reply plus up to five real engine venue objects.
//
// Keep this file in lock-step with the engine: a silent shape change here
// breaks the Ask tab (bamware-ai docs/contracts.md).
import Foundation

/// One turn of the conversation as the engine sees it. Pure wire type —
/// the UI layer wraps it with identity and the venues a reply carried.
public struct ChatMessage: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// The device's current fix, sent only when the location service has one
/// and the user authorized it — the engine then fills `distance_m` on each
/// returned venue.
public struct ChatLocation: Codable, Hashable, Sendable {
    public let lat: Double
    public let lng: Double

    public init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }
}

/// `POST /v1/chat` body. The engine enforces `maxMessages`/`maxMessageLength`
/// and "last message is from the user"; `ChatModel` trims to the same limits
/// client-side so a long session never trips a 400.
public struct ChatRequest: Codable, Hashable, Sendable {
    public static let maxMessages = 10
    public static let maxMessageLength = 500

    public let messages: [ChatMessage]
    public let location: ChatLocation?

    public init(messages: [ChatMessage], location: ChatLocation? = nil) {
        self.messages = messages
        self.location = location
    }
}

/// `200` body. `venues` are real engine venue objects (≤ 5), including
/// `distance_m` when the request carried a location.
public struct ChatResponse: Codable, Hashable, Sendable {
    public struct Meta: Codable, Hashable, Sendable {
        public let model: String
        public let turnsLeftToday: Int

        public init(model: String, turnsLeftToday: Int) {
            self.model = model
            self.turnsLeftToday = turnsLeftToday
        }
    }

    public let reply: String
    public let venues: [Venue]
    public let meta: Meta

    public init(reply: String, venues: [Venue], meta: Meta) {
        self.reply = reply
        self.venues = venues
        self.meta = meta
    }
}

/// Every failure the Ask tab renders a distinct row for. Status → case
/// mapping lives in `VenueAPI.sendChat`; anything that is not one of these
/// is treated as `.upstream` by the UI.
public enum ChatError: Error, Equatable, Sendable {
    /// 401 — signed out, or a signed-in request whose single forced refresh
    /// still came back 401 (`VenueAPIError.authenticationRequired`).
    case signInRequired
    /// 503 `{ "error": "chat_disabled" }` — the engine has chat switched off.
    case disabled
    /// 429 `{ "error": "chat_daily_cap", "resetAt": ISO8601 }`.
    case dailyCap(resetAt: Date?)
    /// 502 `{ "error": "chat_upstream" }` — the engine's model call failed.
    case upstream
    /// Any `URLError` — no network, timeout, DNS.
    case offline
}

/// The one seam the Ask tab talks to. `VenueAPI` is the production
/// conformer; `ScenarioChatClient` is the fixture one.
public protocol ChatClient: Sendable {
    func sendChat(_ request: ChatRequest) async throws -> ChatResponse
}

/// Error body shape every non-2xx chat status shares.
struct ChatErrorBody: Decodable {
    let error: String?
    let resetAt: String?

    static func decode(_ data: Data) -> ChatErrorBody? {
        try? JSONDecoder().decode(ChatErrorBody.self, from: data)
    }

    var resetAtDate: Date? {
        guard let resetAt else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: resetAt) { return date }
        return ISO8601DateFormatter().date(from: resetAt)
    }
}

extension ChatError {
    /// Status + body → `ChatError`, or `nil` when the status is not one the
    /// contract names (callers fall back to `VenueAPIError.http`).
    static func from(statusCode: Int, body: Data) -> ChatError? {
        let decoded = ChatErrorBody.decode(body)
        switch statusCode {
        case 401: return .signInRequired
        case 429: return .dailyCap(resetAt: decoded?.resetAtDate)
        case 502: return .upstream
        case 503: return .disabled
        default: return nil
        }
    }
}
