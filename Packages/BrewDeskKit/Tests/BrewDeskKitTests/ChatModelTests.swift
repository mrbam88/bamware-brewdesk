import Foundation
import Testing
@testable import BrewDeskKit
@testable import VenueKit

/// Ask tab state machine (bamware-brewdesk#247) against a scripted
/// `ChatClient`: transcript growth, every failure phase, retry, the
/// 10-message / 500-char wire caps, and location passthrough.
@Suite struct ChatModelTests {
    private let fixtureVenues = ScenarioChatClient.fixtureVenues

    private func reply(_ text: String, venues: [Venue] = [], turnsLeft: Int = 5) -> ChatResponse {
        ChatResponse(reply: text, venues: venues, meta: .init(model: "test", turnsLeftToday: turnsLeft))
    }

    @Test func sendAppendsUserThenAssistantWithVenues() async {
        let client = ScriptedChatClient(results: [.success(reply("Try Roasters.", venues: fixtureVenues, turnsLeft: 9))])
        let model = ChatModel(client: client)

        await model.send("  Quiet with outlets near me  ")

        #expect(model.transcript.count == 2)
        #expect(model.transcript[0].role == .user)
        #expect(model.transcript[0].text == "Quiet with outlets near me")
        #expect(model.transcript[1].role == .assistant)
        #expect(model.transcript[1].text == "Try Roasters.")
        #expect(model.transcript[1].venues.map(\.id) == ["fixture-roasters", "fixture-library"])
        #expect(model.phase == .idle)
        #expect(model.turnsLeftToday == 9)
    }

    @Test func blankTextIsIgnored() async {
        let client = ScriptedChatClient(results: [])
        let model = ChatModel(client: client)
        await model.send("   \n")
        #expect(model.transcript.isEmpty)
        #expect(client.requests.isEmpty)
    }

    @Test func requestCarriesWholeTranscriptEndingWithUser() async {
        let client = ScriptedChatClient(results: [.success(reply("A")), .success(reply("B"))])
        let model = ChatModel(client: client)

        await model.send("one")
        await model.send("two")

        #expect(client.requests.count == 2)
        let second = client.requests[1]
        #expect(second.messages.map(\.content) == ["one", "A", "two"])
        #expect(second.messages.last?.role == .user)
        #expect(second.location == nil)
    }

    @Test func wireRequestKeepsOnlyTheLastTenMessages() async {
        let client = ScriptedChatClient(results: Array(repeating: .success(reply("ok")), count: 7))
        let model = ChatModel(client: client)

        for index in 1...7 {
            await model.send("message \(index)")
        }

        // 7 user + 6 assistant turns were in the transcript when the 7th
        // request went out — the wire request still carries exactly 10.
        #expect(model.transcript.count == 14)
        let last = client.requests.last!
        #expect(last.messages.count == ChatRequest.maxMessages)
        #expect(last.messages.last?.content == "message 7")
        #expect(last.messages.last?.role == .user)
        // Window is [a2, u3, a3, …, u7]: 13 turns existed, the oldest three
        // (u1, a1, u2) fell off.
        #expect(last.messages.first?.role == .assistant)
        #expect(last.messages[1].content == "message 3")
    }

    @Test func wireMessagesAreClippedToFiveHundredCharacters() async {
        let client = ScriptedChatClient(results: [.success(reply("ok"))])
        let model = ChatModel(client: client)

        await model.send(String(repeating: "x", count: 700))

        #expect(client.requests[0].messages[0].content.count == ChatRequest.maxMessageLength)
    }

    @Test func locationIsPassedWhenProviderHasAFix() async {
        let client = ScriptedChatClient(results: [.success(reply("ok"))])
        let model = ChatModel(client: client, locationProvider: { ChatLocation(lat: 40.7365, lng: -73.9905) })

        await model.send("near me")

        #expect(client.requests[0].location == ChatLocation(lat: 40.7365, lng: -73.9905))
    }

    // MARK: - Failure phases

    @Test func chatErrorsBecomeFailedPhases() async {
        for error in [ChatError.signInRequired, .disabled, .dailyCap(resetAt: nil), .upstream, .offline] {
            let client = ScriptedChatClient(results: [.failure(error)])
            let model = ChatModel(client: client)
            await model.send("hello")
            #expect(model.phase == .failed(error))
            // The user's turn stays so Retry can re-send it.
            #expect(model.transcript.count == 1)
            #expect(model.transcript[0].role == .user)
        }
    }

    @Test func unknownErrorsReadAsUpstream() async {
        let client = ScriptedChatClient(results: [.failure(VenueAPIError.decoding)])
        let model = ChatModel(client: client)
        await model.send("hello")
        #expect(model.phase == .failed(.upstream))
    }

    @Test func retryResendsTheFailedTurnWithoutDuplicatingIt() async {
        let client = ScriptedChatClient(results: [.failure(ChatError.offline), .success(reply("back"))])
        let model = ChatModel(client: client)

        await model.send("hello")
        #expect(model.phase == .failed(.offline))
        await model.retry()

        #expect(model.phase == .idle)
        #expect(model.transcript.map(\.text) == ["hello", "back"])
        #expect(client.requests.count == 2)
        #expect(client.requests[1].messages.map(\.content) == ["hello"])
    }

    @Test func retryIsANoOpWhenNothingFailed() async {
        let client = ScriptedChatClient(results: [])
        let model = ChatModel(client: client)
        await model.retry()
        #expect(client.requests.isEmpty)
        #expect(model.phase == .idle)
    }

    @Test func typingANewMessageAfterAFailureReplacesTheOrphanedTurn() async {
        let client = ScriptedChatClient(results: [.failure(ChatError.upstream), .success(reply("ok"))])
        let model = ChatModel(client: client)

        await model.send("first")
        await model.send("second")

        #expect(model.transcript.map(\.text) == ["second", "ok"])
        #expect(client.requests[1].messages.map(\.content) == ["second"])
    }

    @Test func cancellingSignInPromptDropsTheUnsentTurn() async {
        let client = ScriptedChatClient(results: [.failure(ChatError.signInRequired)])
        let model = ChatModel(client: client)

        await model.send("hello")
        model.cancelSignInPrompt()

        #expect(model.phase == .idle)
        #expect(model.transcript.isEmpty)
    }

    @Test func cancellingSignInPromptIsANoOpForOtherFailures() async {
        let client = ScriptedChatClient(results: [.failure(ChatError.offline)])
        let model = ChatModel(client: client)
        await model.send("hello")
        model.cancelSignInPrompt()
        #expect(model.phase == .failed(.offline))
        #expect(model.transcript.count == 1)
    }

    @Test func retryIsNotAvailableForFlagOrBudgetFailures() {
        #expect(ChatError.upstream.isRetryable)
        #expect(ChatError.offline.isRetryable)
        #expect(!ChatError.disabled.isRetryable)
        #expect(!ChatError.dailyCap(resetAt: nil).isRetryable)
        #expect(!ChatError.signInRequired.isRetryable)
    }
}

/// Answers each `sendChat` from a queue of scripted results and records the
/// requests it saw.
private final class ScriptedChatClient: ChatClient, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<ChatResponse, Error>]
    private(set) var requests: [ChatRequest] = []

    init(results: [Result<ChatResponse, Error>]) {
        self.results = results
    }

    func sendChat(_ request: ChatRequest) async throws -> ChatResponse {
        guard let next = record(request) else { throw ChatError.upstream }
        return try next.get()
    }

    private func record(_ request: ChatRequest) -> Result<ChatResponse, Error>? {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        return results.isEmpty ? nil : results.removeFirst()
    }
}
