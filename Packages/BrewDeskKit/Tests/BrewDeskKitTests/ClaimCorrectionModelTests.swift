import Foundation
import Testing
@testable import BrewDeskKit
@testable import VenueKit

/// Single-claim correction (brewdesk#251): the one-answer payload, the sheet's
/// state machine (editing → submitting → submitted / failed / signInRequired)
/// and the detail screen's refresh from the engine's response.
@Suite struct ClaimCorrectionModelTests {
    private func model(
        _ claim: CorrectableClaim = .laptopPolicy,
        service: any VenueObservationSubmitting
    ) -> ClaimCorrectionModel {
        ClaimCorrectionModel(
            venueId: "fixture-roasters", claim: claim, service: service, submittedBy: "test-device"
        )
    }

    // MARK: Payload

    @Test func submitSendsOnlyTheCorrectedAttribute() async throws {
        let service = RecordingCorrectionService()
        let model = model(service: service)
        model.select(.laptopFriendlyToday(.yes))
        await model.submit()

        let sent = try #require(service.ledger.submissions.first)
        #expect(service.ledger.submissions.count == 1)
        #expect(sent.venueId == "fixture-roasters")
        #expect(sent.submittedBy == "test-device")
        #expect(sent.answers == ObservationAnswers(only: .laptopFriendlyToday(.yes)))
        #expect(sent.answers.laptopFriendlyToday == .yes)
        #expect(sent.answers.seatsAvailable == nil)
        #expect(sent.answers.outletsWorking == nil)
        #expect(sent.answers.noise == nil)
        #expect(sent.answers.wifiQuality == nil)
    }

    @Test func anAnswerForAnotherClaimIsIgnored() async {
        let service = RecordingCorrectionService()
        let model = model(.noise, service: service)
        model.select(.wifiQuality(.fast))
        #expect(model.selection == nil)
        #expect(!model.canSubmit)
        await model.submit()
        #expect(model.phase == .editing)
        #expect(service.ledger.submissions.isEmpty)
    }

    // MARK: State machine

    @Test func noPickDoesNotSubmit() async {
        let service = RecordingCorrectionService()
        let model = model(service: service)
        #expect(!model.canSubmit)
        await model.submit()
        #expect(model.phase == .editing)
        #expect(service.ledger.submissions.isEmpty)
    }

    @Test func editingToSubmittingToSubmitted() async throws {
        let gate = Gate()
        let service = RecordingCorrectionService(gate: gate)
        let model = model(.noise, service: service)
        model.select(.noise(.quiet))
        #expect(model.phase == .editing)
        #expect(model.canSubmit)

        let submit = Task { await model.submit() }
        await gate.waitUntilEntered()
        #expect(model.phase == .submitting)
        #expect(model.isSubmitting)
        #expect(!model.canSubmit)
        // A pick while in flight is ignored.
        model.select(.noise(.loud))
        #expect(model.selection == .noise(.quiet))

        await gate.open()
        await submit.value
        #expect(model.phase == .submitted)
        // The engine's response is what the detail screen refreshes from.
        let updated = try #require(model.updatedVenue)
        #expect(updated.attributes.noise.value == "quiet")
        #expect(updated.attributes.noise.source == "user_report")
    }

    @Test func repeatSubmitAfterSuccessIsANoOp() async {
        let service = RecordingCorrectionService()
        let model = model(service: service)
        model.select(.laptopFriendlyToday(.no))
        await model.submit()
        await model.submit()
        #expect(model.phase == .submitted)
        #expect(service.ledger.submissions.count == 1)
    }

    @Test func failureKeepsThePickWithTheFormsFriendlyCopyAndRetrySucceeds() async {
        let service = RecordingCorrectionService(failures: [URLError(.notConnectedToInternet)])
        let model = model(service: service)
        model.select(.laptopFriendlyToday(.yes))
        await model.submit()

        #expect(model.phase == .failed(
            message: ObservationFormModel.friendlyMessage(for: URLError(.notConnectedToInternet))
        ))
        #expect(model.selection == .laptopFriendlyToday(.yes))
        #expect(model.updatedVenue == nil)
        #expect(model.canSubmit)

        await model.submit() // Retry
        #expect(model.phase == .submitted)
        #expect(service.ledger.submissions.count == 1)
    }

    @Test func engineErrorNeverLeaksAStatusCode() async {
        let service = RecordingCorrectionService(failures: [VenueAPIError.http(statusCode: 500)])
        let model = model(service: service)
        model.select(.laptopFriendlyToday(.yes))
        await model.submit()
        guard case .failed(let message) = model.phase else {
            Issue.record("expected failed, got \(model.phase)")
            return
        }
        #expect(!message.contains("500"))
    }

    @Test func changingThePickAfterAFailureClearsTheError() async {
        let service = RecordingCorrectionService(failures: [VenueAPIError.http(statusCode: 500)])
        let model = model(service: service)
        model.select(.laptopFriendlyToday(.yes))
        await model.submit()
        model.select(.laptopFriendlyToday(.mixed))
        #expect(model.phase == .editing)
        #expect(model.selection == .laptopFriendlyToday(.mixed))
    }

    @Test func authenticationRequiredAsksForSignInThenResubmitsTheSamePick() async {
        let service = RecordingCorrectionService(failures: [VenueAPIError.authenticationRequired])
        let model = model(.wifi, service: service)
        model.select(.wifiQuality(.slow))
        await model.submit()
        #expect(model.phase == .signInRequired)
        #expect(model.selection == .wifiQuality(.slow))

        await model.submit() // what the sheet does once signed in
        #expect(model.phase == .submitted)
        #expect(service.ledger.submissions.map(\.answers) == [ObservationAnswers(only: .wifiQuality(.slow))])
    }

    @Test func cancellingSignInReturnsToEditingWithThePick() async {
        let service = RecordingCorrectionService(failures: [VenueAPIError.authenticationRequired])
        let model = model(service: service)
        model.select(.laptopFriendlyToday(.yes))
        await model.submit()
        model.cancelSignInPrompt()
        #expect(model.phase == .editing)
        #expect(model.selection == .laptopFriendlyToday(.yes))
        #expect(service.ledger.submissions.isEmpty)
    }

    /// The signed-in guard (brewdesk#249) covers a correction exactly as it
    /// covers the full form: a session with no token never reaches the
    /// engine, and the sheet lands in `signInRequired`.
    @Test func aSessionWithNoTokenNeverSendsACorrection() async {
        let upstream = RecordingCorrectionService()
        let guarded = SignedInObservationService(
            hasSession: { true }, accessToken: { nil }, upstream: upstream
        )
        let model = model(service: guarded)
        model.select(.laptopFriendlyToday(.yes))
        await model.submit()
        #expect(model.phase == .signInRequired)
        #expect(upstream.ledger.submissions.isEmpty)
    }

    @Test func signedOutCorrectionsStayAllowed() async {
        let upstream = RecordingCorrectionService()
        let guarded = SignedInObservationService(
            hasSession: { false }, accessToken: { nil }, upstream: upstream
        )
        let model = model(service: guarded)
        model.select(.laptopFriendlyToday(.yes))
        await model.submit()
        #expect(model.phase == .submitted)
        #expect(upstream.ledger.submissions.count == 1)
    }

    // MARK: Detail refresh

    private var detailVenue: Venue {
        get throws {
            try #require(ScenarioVenueService.fixtureVenues.first { $0.id == "fixture-roasters" })
        }
    }

    @MainActor
    @Test func aSuccessfulCorrectionRefreshesTheDetailFromTheEnginesResponse() async throws {
        let shown = try detailVenue
        let model = model(.noise, service: ScenarioVenueService(scenario: .fixtureOK))
        model.select(.noise(.quiet))
        await model.submit()
        let response = try #require(model.updatedVenue)

        let ledger = ClaimCorrectionLedger()
        #expect(ledger.current(shown) == shown)
        ledger.record(response)
        let refreshed = ledger.current(shown)

        // The corrected row shows the engine's claim…
        #expect(refreshed.attributes.noise == response.attributes.noise)
        #expect(refreshed.attributes.noise.value == "quiet")
        // …the rows that were not corrected are exactly as they were…
        #expect(refreshed.attributes.wifi == shown.attributes.wifi)
        #expect(refreshed.attributes.outlets == shown.attributes.outlets)
        #expect(refreshed.attributes.laptopPolicy == shown.attributes.laptopPolicy)
        // …and nothing the write response does not own is lost.
        #expect(refreshed.hoursRaw == shown.hoursRaw)
        #expect(refreshed.website == shown.website)
        #expect(refreshed.distanceM == shown.distanceM)
    }

    @MainActor
    @Test func theRefreshKeepsBusinessInfoTheWriteResponseDoesNotCarry() throws {
        let shown = try detailVenue
        let bare = Venue(
            id: shown.id, name: shown.name, lat: shown.lat, lng: shown.lng, address: nil,
            neighborhood: shown.neighborhood, borough: shown.borough, hoursRaw: nil,
            vertical: shown.vertical,
            attributes: VenueAttributes(
                wifi: shown.attributes.wifi,
                outlets: shown.attributes.outlets,
                laptopPolicy: Claim(
                    value: "unrestricted", source: "user_report", confidence: 0.7,
                    observedAt: "2026-11-16T12:00:00.000Z"
                ),
                noise: shown.attributes.noise
            ),
            vibeTags: [], workScore: 91, lastVerified: "2026-11-16T12:00:00.000Z", distanceM: nil
        )
        let ledger = ClaimCorrectionLedger()
        ledger.record(bare)
        let refreshed = ledger.current(shown)
        #expect(refreshed.attributes.laptopPolicy.value == "unrestricted")
        #expect(refreshed.workScore == 91)
        #expect(refreshed.hoursRaw == shown.hoursRaw)
        #expect(refreshed.address == shown.address)
        #expect(refreshed.vibeTags == shown.vibeTags)
    }

    @MainActor
    @Test func aFresherCopyFromTheOpenerWinsOverTheLedger() throws {
        let shown = try detailVenue
        let response = Venue(
            id: shown.id, name: shown.name, lat: shown.lat, lng: shown.lng, address: nil,
            neighborhood: shown.neighborhood, borough: shown.borough, hoursRaw: nil,
            vertical: shown.vertical, attributes: shown.attributes, vibeTags: [],
            workScore: 10, lastVerified: "2026-07-01T00:00:00Z", distanceM: nil
        )
        let ledger = ClaimCorrectionLedger()
        ledger.record(response)
        // `shown` was verified 2026-08-01 — newer than the recorded response.
        #expect(ledger.current(shown) == shown)
    }

    @MainActor
    @Test func theLedgerNeverLeaksOneVenuesCorrectionOntoAnother() throws {
        let shown = try detailVenue
        let other = try #require(ScenarioVenueService.fixtureVenues.first { $0.id != shown.id })
        let ledger = ClaimCorrectionLedger()
        ledger.record(other)
        #expect(ledger.current(shown) == shown)
        #expect(shown.applyingEngineClaims(from: other) == shown)
    }
}

// MARK: - Test doubles

/// Scripted failures, then the fixture engine's own answer (so the returned
/// venue really carries the corrected claim). Records every payload that got
/// through.
private struct RecordingCorrectionService: VenueObservationSubmitting {
    struct Submission: Equatable, Sendable {
        let venueId: String
        let submittedBy: String
        let answers: ObservationAnswers
    }

    final class Ledger: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [Submission] = []
        private var failures: [any Error]

        init(failures: [any Error]) { self.failures = failures }

        var submissions: [Submission] { lock.withLock { recorded } }
        func nextFailure() -> (any Error)? { lock.withLock { failures.isEmpty ? nil : failures.removeFirst() } }
        func record(_ submission: Submission) { lock.withLock { recorded.append(submission) } }
    }

    let ledger: Ledger
    let gate: Gate?

    init(failures: [any Error] = [], gate: Gate? = nil) {
        ledger = Ledger(failures: failures)
        self.gate = gate
    }

    func submitObservation(
        venueId: String,
        submittedBy: String,
        answers: ObservationAnswers
    ) async throws -> Venue {
        await gate?.enter()
        if let failure = ledger.nextFailure() { throw failure }
        ledger.record(Submission(venueId: venueId, submittedBy: submittedBy, answers: answers))
        return try await ScenarioVenueService(scenario: .fixtureOK).submitObservation(
            venueId: venueId, submittedBy: submittedBy, answers: answers
        )
    }
}

/// Holds a submit in flight so a test can observe `.submitting`.
private actor Gate {
    private var entered = false
    private var isOpen = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        entered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters = []
        if !isOpen {
            await withCheckedContinuation { openWaiters.append($0) }
        }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func open() {
        isOpen = true
        openWaiters.forEach { $0.resume() }
        openWaiters = []
    }
}
