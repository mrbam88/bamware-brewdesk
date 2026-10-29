// Ask tab state machine (bamware-brewdesk#247): transcript, one in-flight
// send at a time, typed failure phases, and the engine's turn budget.
import Foundation
import Observation
import VenueKit

/// One bubble in the transcript. Wraps the wire `ChatMessage` with identity
/// (for `ForEach`) and, on an assistant turn, the venues the reply grounded
/// itself in — the cards rendered under that bubble.
public struct ChatTranscriptEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let role: ChatMessage.Role
    public let text: String
    public let venues: [Venue]

    public init(id: UUID = UUID(), role: ChatMessage.Role, text: String, venues: [Venue] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.venues = venues
    }

    var wireMessage: ChatMessage {
        ChatMessage(role: role, content: String(text.prefix(ChatRequest.maxMessageLength)))
    }
}

@Observable
public final class ChatModel {
    public enum Phase: Equatable {
        case idle
        case sending
        /// The failed turn's user message stays at the end of `transcript`
        /// so `retry()` can re-send it without the user retyping.
        case failed(ChatError)
    }

    public private(set) var transcript: [ChatTranscriptEntry] = []
    public private(set) var phase: Phase = .idle
    /// From the last successful reply's `meta`; nil until one arrives.
    public private(set) var turnsLeftToday: Int?

    /// Empty-state suggestion chips — tapping one sends it verbatim.
    public static let suggestions: [String] = [
        String(localized: "Quiet with outlets near me"),
        String(localized: "Fast Wi-Fi in Williamsburg"),
        String(localized: "Open late, laptop friendly")
    ]

    @ObservationIgnored private let client: any ChatClient
    /// The device's current fix when authorized, nil otherwise — the view
    /// layer owns the `LocationService` (an app-target type), so it hands
    /// the model a closure rather than the service.
    @ObservationIgnored private let locationProvider: () -> ChatLocation?

    public init(
        client: any ChatClient,
        locationProvider: @escaping () -> ChatLocation? = { nil }
    ) {
        self.client = client
        self.locationProvider = locationProvider
    }

    public var isSending: Bool { phase == .sending }

    /// Appends the user's turn and asks the engine. Ignored while a send is
    /// in flight or when `text` is blank after trimming.
    public func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, phase != .sending else { return }
        // A retry supersedes the failed turn: if the user typed something
        // new instead of tapping Retry, drop the orphaned user bubble so
        // the wire transcript never carries two user turns in a row.
        if case .failed = phase, transcript.last?.role == .user {
            transcript.removeLast()
        }
        transcript.append(ChatTranscriptEntry(role: .user, text: trimmed))
        await perform()
    }

    /// Re-sends the failed turn still sitting at the end of the transcript.
    /// A no-op unless `phase` is `.failed`.
    public func retry() async {
        guard case .failed = phase, transcript.last?.role == .user else { return }
        await perform()
    }

    /// Dismissing the sign-in prompt without signing in: back to `.idle`,
    /// the unsent user turn is dropped (same shape as
    /// `ObservationFormModel.cancelSignInPrompt`).
    public func cancelSignInPrompt() {
        guard phase == .failed(.signInRequired) else { return }
        if transcript.last?.role == .user { transcript.removeLast() }
        phase = .idle
    }

    /// The wire request for the current transcript: last `maxMessages`
    /// turns, each clipped to `maxMessageLength`, plus the device fix when
    /// the provider has one.
    func makeRequest() -> ChatRequest {
        ChatRequest(
            messages: transcript.suffix(ChatRequest.maxMessages).map(\.wireMessage),
            location: locationProvider()
        )
    }

    private func perform() async {
        phase = .sending
        do {
            let response = try await client.sendChat(makeRequest())
            transcript.append(
                ChatTranscriptEntry(role: .assistant, text: response.reply, venues: response.venues)
            )
            turnsLeftToday = response.meta.turnsLeftToday
            phase = .idle
        } catch let error as ChatError {
            phase = .failed(error)
        } catch is CancellationError {
            // The view went away mid-send; leave the user turn for a retry.
            phase = .failed(.offline)
        } catch {
            phase = .failed(.upstream)
        }
    }
}

extension ChatError {
    /// The one sentence the Ask tab shows for this failure. Raw errors and
    /// status codes never reach the UI.
    public var userMessage: String {
        switch self {
        case .signInRequired:
            String(localized: "Sign in to ask")
        case .disabled:
            String(localized: "Ask is taking a break. The map still works.")
        case .dailyCap:
            String(localized: "You've used today's questions. Back tomorrow.")
        case .upstream, .offline:
            String(localized: "Couldn't reach BrewDesk. Try again.")
        }
    }

    /// Whether a Retry button makes sense: a flag that is off or a budget
    /// that is spent will not change by tapping again.
    public var isRetryable: Bool {
        switch self {
        case .upstream, .offline: true
        case .signInRequired, .disabled, .dailyCap: false
        }
    }
}

/// Same `-UITestScenario` seam `ObservationServiceResolver` uses: a scenario
/// launch gets the fixture client, everything else the real engine with the
/// signed-in bearer policy (`BrewDeskAccountTenant`).
public enum ChatClientResolver {
    public static func resolve(
        environment: LaunchEnvironment = .current,
        baseURL: URL = VenueAPI.defaultBaseURL
    ) -> any ChatClient {
        if let scenario = environment.scenario {
            return ScenarioChatClient(scenario: scenario)
        }
        return VenueAPI(
            baseURL: baseURL,
            tokenProvider: { await BrewDeskAccountTenant.freshAccessToken(environment: environment) },
            tokenRefresher: { await BrewDeskAccountTenant.refreshAccessTokenAfterUnauthorized(environment: environment) }
        )
    }
}
