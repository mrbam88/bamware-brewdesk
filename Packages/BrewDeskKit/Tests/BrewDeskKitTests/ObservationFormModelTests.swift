import Foundation
import Testing
import VenueKit
@testable import BrewDeskKit

/// Form state machine (brewdesk#47): gating, payload, failure → Retry, and
/// the per-install submitter identity.
@Suite struct ObservationFormModelTests {
    private var answers: ObservationAnswers {
        ObservationAnswers(
            laptopFriendlyToday: .yes,
            seatsAvailable: .plenty,
            outletsWorking: .few,
            noise: .moderate
        )
    }

    private func completedModel(
        service: MockObservationService,
        submittedBy: String = "test-device"
    ) -> ObservationFormModel {
        let model = ObservationFormModel(
            venueId: "fixture-roasters", service: service, submittedBy: submittedBy
        )
        model.select(laptopFriendly: .yes)
        model.select(seats: .plenty)
        model.select(outlets: .few)
        model.select(noise: .moderate)
        return model
    }

    // MARK: Gating

    @Test func incompleteFormDoesNotSubmit() async {
        let service = MockObservationService()
        let model = ObservationFormModel(
            venueId: "fixture-roasters", service: service, submittedBy: "test-device"
        )
        model.select(laptopFriendly: .yes)
        model.select(seats: .plenty)
        model.select(outlets: .few)
        // noise unanswered
        #expect(!model.isComplete)
        await model.submit()
        #expect(model.phase == .editing)
        #expect(service.ledger.submissions.isEmpty)
    }

    @Test func allFourAnswersComplete() {
        let model = completedModel(service: MockObservationService())
        #expect(model.isComplete)
        #expect(model.phase == .editing)
    }

    // MARK: Submit

    @Test func submitSendsTheExactPayloadAndThanks() async throws {
        let service = MockObservationService()
        let model = completedModel(service: service, submittedBy: "device-abc")
        await model.submit()

        #expect(model.phase == .submitted)
        let recorded = try #require(service.ledger.submissions.first)
        #expect(service.ledger.submissions.count == 1)
        #expect(recorded.venueId == "fixture-roasters")
        #expect(recorded.submittedBy == "device-abc")
        #expect(recorded.answers == answers)
    }

    @Test func repeatSubmitAfterSuccessIsANoOp() async {
        let service = MockObservationService()
        let model = completedModel(service: service)
        await model.submit()
        await model.submit()
        #expect(service.ledger.submissions.count == 1)
    }

    // MARK: Failure and retry

    @Test func failureKeepsAnswersAndRetrySucceeds() async {
        let service = MockObservationService(failuresRemaining: 1)
        let model = completedModel(service: service)

        await model.submit()
        guard case .failed = model.phase else {
            Issue.record("expected .failed, got \(model.phase)")
            return
        }
        // Answers survive the failure — Retry re-submits the same payload.
        #expect(model.isComplete)

        await model.submit()
        #expect(model.phase == .submitted)
        #expect(service.ledger.submissions.count == 1)
        #expect(service.ledger.submissions.first?.answers == answers)
    }

    @Test func changingAnAnswerClearsTheFailureBanner() async {
        let service = MockObservationService(failuresRemaining: 1)
        let model = completedModel(service: service)
        await model.submit()
        guard case .failed = model.phase else {
            Issue.record("expected .failed, got \(model.phase)")
            return
        }
        model.select(noise: .loud)
        #expect(model.phase == .editing)
    }

    @Test func offlineFailuresGetTheOfflineCopyOthersTheGenericCopy() {
        let offline = ObservationFormModel.friendlyMessage(for: URLError(.notConnectedToInternet))
        let engineDown = ObservationFormModel.friendlyMessage(
            for: VenueAPIError.http(statusCode: 500)
        )
        #expect(offline.contains("offline"))
        #expect(!engineDown.isEmpty)
        // Friendly copy only — no raw status codes reach the UI.
        #expect(!engineDown.contains("500"))
    }

    // MARK: Submitter identity (brewdesk#48 upgrade point)

    @Test func submitterIDIsMintedOnceAndStable() throws {
        let suite = "observation-identity-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = ObservationSubmitterIdentity.submitterID(defaults: defaults)
        let second = ObservationSubmitterIdentity.submitterID(defaults: defaults)
        #expect(!first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(first == second)
        #expect(UUID(uuidString: first) != nil)
    }

    @Test func submitterIDsDifferPerInstall() throws {
        let suiteA = "observation-identity-a-\(UUID().uuidString)"
        let suiteB = "observation-identity-b-\(UUID().uuidString)"
        let defaultsA = try #require(UserDefaults(suiteName: suiteA))
        let defaultsB = try #require(UserDefaults(suiteName: suiteB))
        defer {
            defaultsA.removePersistentDomain(forName: suiteA)
            defaultsB.removePersistentDomain(forName: suiteB)
        }
        #expect(
            ObservationSubmitterIdentity.submitterID(defaults: defaultsA)
                != ObservationSubmitterIdentity.submitterID(defaults: defaultsB)
        )
    }

    // MARK: Default-service resolution (RootView untouched — brewdesk#47)

    @Test func resolverHonoursTheScenarioLaunchArgument() {
        let resolved = ObservationServiceResolver.resolve(
            arguments: ["-UITestScenario", "engineDown"]
        )
        let scenario = resolved as? ScenarioVenueService
        #expect(scenario?.scenario == .engineDown)
    }

    @Test func resolverFallsBackToVenueAPIOnNormalLaunches() {
        #expect(ObservationServiceResolver.resolve(arguments: []) is VenueAPI)
        #expect(
            ObservationServiceResolver.resolve(arguments: ["-UITestScenario", "not-a-scenario"])
                is VenueAPI
        )
    }
}

// MARK: - Mock

/// Same shape as `MockCaptureSubmissionService`: scripted failures + recorded
/// payloads. A Sendable value type with a locked ledger so it satisfies the
/// nonisolated `VenueObservationSubmitting` seam from MainActor tests.
private struct MockObservationService: VenueObservationSubmitting {
    struct Submission: Equatable, Sendable {
        let venueId: String
        let submittedBy: String
        let answers: ObservationAnswers
    }

    final class Ledger: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [Submission] = []
        private var failures: Int

        init(failuresRemaining: Int) {
            failures = failuresRemaining
        }

        var submissions: [Submission] {
            lock.withLock { recorded }
        }

        func consumeFailure() -> Bool {
            lock.withLock {
                guard failures > 0 else { return false }
                failures -= 1
                return true
            }
        }

        func record(_ submission: Submission) {
            lock.withLock { recorded.append(submission) }
        }
    }

    let ledger: Ledger

    init(failuresRemaining: Int = 0) {
        ledger = Ledger(failuresRemaining: failuresRemaining)
    }

    func submitObservation(
        venueId: String,
        submittedBy: String,
        answers: ObservationAnswers
    ) async throws -> Venue {
        if ledger.consumeFailure() {
            throw VenueAPIError.http(statusCode: 500)
        }
        ledger.record(
            Submission(venueId: venueId, submittedBy: submittedBy, answers: answers)
        )
        return ScenarioVenueService.fixtureVenues[0]
    }
}
