// Fixture `ChatClient` for `-UITestScenario` launches and package tests
// (bamware-brewdesk#247). Mirrors `ScenarioVenueService`'s scenario
// vocabulary so one launch argument drives the venue, photo, and chat
// services together — no network, deterministic replies.
import Foundation

public struct ScenarioChatClient: ChatClient, Sendable {
    public typealias Scenario = ScenarioVenueService.Scenario

    public let scenario: Scenario

    public init(scenario: Scenario) {
        self.scenario = scenario
    }

    /// Two sentences, always the same — a UI test can match it literally.
    public static let fixtureReply =
        "Fixture Roasters is your best bet: fast Wi-Fi, plenty of outlets, and laptops are welcome all day. "
        + "Fixture Reading Room is the quieter fallback a few blocks south."

    public static let emptyReply =
        "Nothing in our data matches that yet. Try a different neighborhood, or browse the map for what is nearby."

    /// Roasters + Reading Room — the two fixtures every scenario-driven UI
    /// test already knows by name (`FilterUITests`, `SearchUITests`).
    public static let fixtureVenues: [Venue] = Array(
        ScenarioVenueService.fixtureVenues.filter { $0.id == "fixture-roasters" || $0.id == "fixture-library" }
    )

    public static let fixtureMeta = ChatResponse.Meta(model: "fixture", turnsLeftToday: 19)

    public func sendChat(_ request: ChatRequest) async throws -> ChatResponse {
        switch scenario {
        case .engineDown:
            throw ChatError.upstream
        case .offline:
            throw ChatError.offline
        case .emptyVenues, .noCoverage:
            return ChatResponse(reply: Self.emptyReply, venues: [], meta: Self.fixtureMeta)
        case .slow:
            // Same 6 s the venue fetch uses so the "thinking" indicator is
            // visible long enough to eyeball; cancellation-honouring.
            try await Task.sleep(for: .seconds(6))
            return ChatResponse(reply: Self.fixtureReply, venues: Self.fixtureVenues, meta: Self.fixtureMeta)
        default:
            return ChatResponse(reply: Self.fixtureReply, venues: Self.fixtureVenues, meta: Self.fixtureMeta)
        }
    }
}
