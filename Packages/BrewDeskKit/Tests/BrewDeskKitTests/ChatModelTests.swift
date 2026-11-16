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

    // MARK: - Wait stages (brewdesk#272)

    /// Starts a send that stays pending until the test resolves `client`,
    /// and returns once the model's ticker is parked on the manual clock.
    private func startPendingSend(
        _ model: ChatModel,
        clock: ManualClock
    ) async -> Task<Void, Never> {
        let send = Task { await model.send("hello") }
        await clock.waitForSleeper()
        return send
    }

    @Test func waitStageFollowsTheClockAtZeroFiveAndTwentySeconds() async {
        let client = PendingChatClient()
        let clock = ManualClock()
        let model = ChatModel(client: client, clock: clock)
        let send = await startPendingSend(model, clock: clock)

        // 0 s
        #expect(model.phase == .sending)
        #expect(model.waitStage == .thinking)
        #expect(model.waitStage.message == "Thinking…")

        // Just short of 5 s: still thinking.
        clock.advance(by: .milliseconds(4_900))
        await settle()
        #expect(model.waitStage == .thinking)

        // 5 s
        clock.advance(by: .milliseconds(100))
        await clock.waitForSleeper()
        #expect(model.waitStage == .wakingUp)
        #expect(model.waitStage.message == "Waking up BrewDesk…")

        // 19.9 s: still waking up.
        clock.advance(by: .milliseconds(14_900))
        await settle()
        #expect(model.waitStage == .wakingUp)

        // 20 s
        clock.advance(by: .milliseconds(100))
        await until { model.waitStage == .stillWorking }
        #expect(model.waitStage == .stillWorking)
        #expect(model.waitStage.message == "Still working on it…")

        // Nothing later than 20 s changes it.
        clock.advance(by: .seconds(60))
        await settle()
        #expect(model.waitStage == .stillWorking)
        #expect(model.phase == .sending)

        client.resolve(.success(reply("ok")))
        await send.value
    }

    @Test func waitStageResetsWhenTheReplyArrives() async {
        let client = PendingChatClient()
        let clock = ManualClock()
        let model = ChatModel(client: client, clock: clock)
        let send = await startPendingSend(model, clock: clock)

        clock.advance(by: .seconds(5))
        await clock.waitForSleeper()
        #expect(model.waitStage == .wakingUp)

        client.resolve(.success(reply("awake")))
        await send.value

        #expect(model.phase == .idle)
        #expect(model.waitStage == .thinking)
        // The cancelled ticker must not relabel anything afterwards.
        clock.advance(by: .seconds(60))
        await settle()
        #expect(model.waitStage == .thinking)
    }

    @Test func waitStageResetsWhenTheSendFails() async {
        let client = PendingChatClient()
        let clock = ManualClock()
        let model = ChatModel(client: client, clock: clock)
        let send = await startPendingSend(model, clock: clock)

        clock.advance(by: .seconds(20))
        await until { model.waitStage == .stillWorking }
        #expect(model.waitStage == .stillWorking)

        client.resolve(.failure(ChatError.upstream))
        await send.value

        #expect(model.phase == .failed(.upstream))
        #expect(model.waitStage == .thinking)
        clock.advance(by: .seconds(60))
        await settle()
        #expect(model.waitStage == .thinking)
    }

    @Test func aRetryStartsTheWaitOverFromThinking() async {
        let client = PendingChatClient()
        let clock = ManualClock()
        let model = ChatModel(client: client, clock: clock)
        let send = await startPendingSend(model, clock: clock)
        clock.advance(by: .seconds(5))
        await clock.waitForSleeper()
        client.resolve(.failure(ChatError.offline))
        await send.value

        let retry = Task { await model.retry() }
        await clock.waitForSleeper()
        #expect(model.phase == .sending)
        #expect(model.waitStage == .thinking)
        // 4 s into the retry is not 5 s, whatever the first try waited.
        clock.advance(by: .seconds(4))
        await settle()
        #expect(model.waitStage == .thinking)
        clock.advance(by: .seconds(1))
        await clock.waitForSleeper()
        #expect(model.waitStage == .wakingUp)

        client.resolve(.success(reply("back")))
        await retry.value
        #expect(model.waitStage == .thinking)
    }

    @Test func waitStageThresholdsAreFiveAndTwentySeconds() {
        #expect(ChatModel.WaitStage.thinking.threshold == .zero)
        #expect(ChatModel.WaitStage.wakingUp.threshold == .seconds(5))
        #expect(ChatModel.WaitStage.stillWorking.threshold == .seconds(20))
    }

    /// Lets already-runnable main-actor work (a ticker woken by `advance`)
    /// run. Used only to assert that nothing changed.
    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    /// Yields until `condition` holds; gives up after a bounded number of
    /// turns so a broken ticker fails the `#expect` that follows instead of
    /// hanging the suite.
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() { await Task.yield() }
    }
}

/// A `ChatClient` whose reply the test supplies later, so a send can be
/// held in flight while a manual clock moves.
private final class PendingChatClient: ChatClient, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<ChatResponse, Error>] = []
    private var queued: [Result<ChatResponse, Error>] = []

    func sendChat(_ request: ChatRequest) async throws -> ChatResponse {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if queued.isEmpty {
                waiters.append(continuation)
                lock.unlock()
            } else {
                let result = queued.removeFirst()
                lock.unlock()
                continuation.resume(with: result)
            }
        }
    }

    nonisolated func resolve(_ result: Result<ChatResponse, Error>) {
        lock.lock()
        if waiters.isEmpty {
            queued.append(result)
            lock.unlock()
        } else {
            let waiter = waiters.removeFirst()
            lock.unlock()
            waiter.resume(with: result)
        }
    }
}

/// A clock that only moves when the test says so. `sleep` parks until
/// `advance(by:)` carries `now` past its deadline; cancellation throws, as
/// `ContinuousClock` does.
private final class ManualClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let id: UInt64
        let deadline: Instant
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [Sleeper] = []
    private var nextID: UInt64 = 0
    private var sleeperWaiters: [CheckedContinuation<Void, Never>] = []

    nonisolated var now: Instant {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    nonisolated var minimumResolution: Duration { .zero }

    nonisolated func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = nextIdentifier()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                park(Sleeper(id: id, deadline: deadline, continuation: continuation))
            }
        } onCancel: {
            cancel(id)
        }
    }

    /// Moves time forward and wakes every sleeper whose deadline passed.
    nonisolated func advance(by duration: Duration) {
        lock.lock()
        current = current.advanced(by: duration)
        let due = sleepers.filter { $0.deadline <= current }
        sleepers.removeAll { $0.deadline <= current }
        lock.unlock()
        for sleeper in due { sleeper.continuation.resume() }
    }

    /// Returns once some task is parked in `sleep` — the model's ticker has
    /// reached its next wait, so everything before that wait has happened.
    nonisolated func waitForSleeper() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if sleepers.isEmpty {
                sleeperWaiters.append(continuation)
                lock.unlock()
            } else {
                lock.unlock()
                continuation.resume()
            }
        }
    }

    private nonisolated func nextIdentifier() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        nextID += 1
        return nextID
    }

    private nonisolated func park(_ sleeper: Sleeper) {
        lock.lock()
        if Task.isCancelled {
            lock.unlock()
            sleeper.continuation.resume(throwing: CancellationError())
            return
        }
        if sleeper.deadline <= current {
            lock.unlock()
            sleeper.continuation.resume()
            return
        }
        sleepers.append(sleeper)
        let waiting = sleeperWaiters
        sleeperWaiters.removeAll()
        lock.unlock()
        for waiter in waiting { waiter.resume() }
    }

    private nonisolated func cancel(_ id: UInt64) {
        lock.lock()
        let index = sleepers.firstIndex { $0.id == id }
        let sleeper = index.map { sleepers.remove(at: $0) }
        lock.unlock()
        sleeper?.continuation.resume(throwing: CancellationError())
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
