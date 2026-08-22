// Structured observation form — state machine + wiring (brewdesk#47).
// Unlike the Debug-only capture prototype (#46), this SHIPS: the review form
// IS an observation. Spec: issue #47; wire contract: bamware-venue-engine PR #26.
import Foundation
import SwiftUI
import VenueKit

/// The stable anonymous per-install submitter id (`submittedBy` v1).
///
/// Auth v1 is an opaque token the engine only checks for non-emptiness
/// (401 when missing/empty) — it is NOT verified against any account system.
/// UPGRADE POINT (brewdesk#48): real accounts replace this UUID with a
/// server-validated identity; the endpoint shape will not change, so only
/// this type and the model's default `submittedBy` argument should move.
///
/// Privacy: the UUID is random, generated on device, stored only in
/// UserDefaults (already declared, reason CA92.1), and never leaves the
/// device except inside an observation submit. It identifies an install,
/// not a person — but it IS an identifier travelling off-device, so the
/// App Privacy answer must be revisited before the next store submission
/// (flagged on the #47 PR; store submissions are a Bilal-only gate).
public enum ObservationSubmitterIdentity {
    static let defaultsKey = "brewdesk.observation.submitter-id"

    /// Returns the existing id, or mints and persists one. Injectable
    /// defaults keep package tests off `.standard`.
    public static func submitterID(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: defaultsKey)
        return fresh
    }
}

/// Drives the five-question form: answer → submit → thanked, with a friendly
/// failed state whose Retry re-submits the same answers. All transition rules
/// live here so they are unit-testable without UI (same policy as
/// `CaptureFlowModel`).
@Observable
public final class ObservationFormModel {
    public enum Phase: Equatable {
        case editing
        case submitting
        /// `message` is the friendly, user-facing sentence — never a raw error.
        case failed(message: String)
        case submitted
    }

    public let venueId: String
    public private(set) var laptopFriendly: LaptopFriendlyAnswer?
    public private(set) var seats: AvailabilityAnswer?
    public private(set) var outlets: AvailabilityAnswer?
    public private(set) var noise: NoiseAnswer?
    public private(set) var wifiQuality: WifiQualityAnswer? // brewdesk#79
    public private(set) var phase: Phase = .editing

    private let service: any VenueObservationSubmitting
    private let submittedBy: String

    public init(
        venueId: String,
        service: any VenueObservationSubmitting,
        submittedBy: String = ObservationSubmitterIdentity.submitterID()
    ) {
        self.venueId = venueId
        self.service = service
        self.submittedBy = submittedBy
    }

    // MARK: Derived state

    public var isComplete: Bool {
        laptopFriendly != nil && seats != nil && outlets != nil && noise != nil
            && wifiQuality != nil
    }

    public var isSubmitting: Bool { phase == .submitting }

    // MARK: Selection
    // Selecting (or re-selecting) an answer while failed returns the form to
    // editing — the stale error banner must not outlive a changed answer.

    public func select(laptopFriendly answer: LaptopFriendlyAnswer) {
        guard canEdit else { return }
        laptopFriendly = answer
        clearFailureAfterEdit()
    }

    public func select(seats answer: AvailabilityAnswer) {
        guard canEdit else { return }
        seats = answer
        clearFailureAfterEdit()
    }

    public func select(outlets answer: AvailabilityAnswer) {
        guard canEdit else { return }
        outlets = answer
        clearFailureAfterEdit()
    }

    public func select(noise answer: NoiseAnswer) {
        guard canEdit else { return }
        noise = answer
        clearFailureAfterEdit()
    }

    public func select(wifiQuality answer: WifiQualityAnswer) {
        guard canEdit else { return }
        wifiQuality = answer
        clearFailureAfterEdit()
    }

    // MARK: Submit

    /// No-op unless all five answers are present and no submit is in flight.
    /// Failure keeps every answer — Retry is this same method.
    public func submit() async {
        guard isComplete,
              let laptopFriendly, let seats, let outlets, let noise, let wifiQuality,
              phase != .submitting, phase != .submitted
        else { return }
        phase = .submitting
        do {
            _ = try await service.submitObservation(
                venueId: venueId,
                submittedBy: submittedBy,
                answers: ObservationAnswers(
                    laptopFriendlyToday: laptopFriendly,
                    seatsAvailable: seats,
                    outletsWorking: outlets,
                    noise: noise,
                    wifiQuality: wifiQuality
                )
            )
            phase = .submitted
        } catch {
            phase = .failed(message: Self.friendlyMessage(for: error))
        }
    }

    private var canEdit: Bool {
        switch phase {
        case .editing, .failed: true
        case .submitting, .submitted: false
        }
    }

    private func clearFailureAfterEdit() {
        if case .failed = phase { phase = .editing }
    }

    /// Friendly copy only — raw errors and status codes never reach the UI.
    static func friendlyMessage(for error: Error) -> String {
        if let urlError = error as? URLError,
           urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
            return String(localized: "You look offline — your answers are saved here. Try again in a moment.")
        }
        return String(localized: "Couldn't send this right now. Your answers are still here — try again in a moment.")
    }
}

// MARK: - Service injection

/// Optional-first observation service injection, mirroring
/// `\.venuePhotoService`: screens read it from the environment; nil (the
/// default) means the entry resolves `ObservationServiceResolver.default()`
/// when the form opens. Resolved down here rather than in RootView so the
/// feature stays additive to the composition root.
private struct VenueObservationServiceKey: EnvironmentKey {
    static let defaultValue: (any VenueObservationSubmitting)? = nil
}

extension EnvironmentValues {
    public var venueObservationService: (any VenueObservationSubmitting)? {
        get { self[VenueObservationServiceKey.self] }
        set { self[VenueObservationServiceKey.self] = newValue }
    }
}

/// Default-service resolution honouring the same `-UITestScenario` launch
/// argument contract as RootView (see `UITestScenario` in the app target):
/// scenario launches get the deterministic `ScenarioVenueService`, every
/// normal launch gets the production `VenueAPI`. Inert otherwise — one
/// argument scan at form-open time.
public enum ObservationServiceResolver {
    public static func resolve(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> any VenueObservationSubmitting {
        if let index = arguments.firstIndex(of: "-UITestScenario"),
           arguments.indices.contains(index + 1),
           let scenario = ScenarioVenueService.Scenario(rawValue: arguments[index + 1]) {
            return ScenarioVenueService(scenario: scenario)
        }
        return VenueAPI()
    }
}
