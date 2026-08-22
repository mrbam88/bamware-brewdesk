import Foundation

// Structured community observations (brewdesk#47, #79). The review form IS an
// observation: five enum-valued answers, no free text anywhere — the engine's
// schema is `.strict()` at both levels, so any extra key is a 400. Wire
// contract: bamware-venue-engine PR #26, `POST /v1/venues/:id/observations`;
// `wifiQuality` added by brewdesk#79 (optional on the wire, so pre-#79 builds
// keep submitting four answers successfully).

/// "Laptop-friendly today?" — maps to the engine's laptopPolicy claim
/// (yes → unrestricted, mixed → time_limited, no → discouraged).
public enum LaptopFriendlyAnswer: String, CaseIterable, Codable, Equatable, Sendable {
    case yes, mixed, no
}

/// "None / a few / plenty" for seats and outlets — maps to the engine's
/// seating/outlets vocabulary (none → scarce, few → some, plenty → plenty).
/// The `none` wire value gets a distinct case name so an optional selection
/// (`AvailabilityAnswer?`) can never confuse it with `Optional.none`.
public enum AvailabilityAnswer: String, CaseIterable, Codable, Equatable, Sendable {
    case noneAvailable = "none"
    case few
    case plenty
}

/// "How loud is it?" — maps to the engine's noise vocabulary
/// (quiet → quiet, moderate → moderate, loud → lively).
public enum NoiseAnswer: String, CaseIterable, Codable, Equatable, Sendable {
    case quiet, moderate, loud
}

/// "How's the Wi-Fi?" (brewdesk#79) — maps to the engine's EXISTING WifiTier
/// claim vocabulary (fast → fast, acceptable → ok, slow → slow,
/// unusable → slow; the verbatim answer is kept on the stored observation).
/// Lands as a user_report claim like every other answer.
public enum WifiQualityAnswer: String, CaseIterable, Codable, Equatable, Sendable {
    case fast, acceptable, slow, unusable
}

/// All five answers — every field required, by construction (the engine
/// accepts `wifiQuality` as optional only so pre-#79 builds keep working;
/// this app always sends it). There is no free-text member and never should
/// be: structure is what makes community input scoreable (epic brewdesk#25).
public struct ObservationAnswers: Codable, Equatable, Sendable {
    public let laptopFriendlyToday: LaptopFriendlyAnswer
    public let seatsAvailable: AvailabilityAnswer
    public let outletsWorking: AvailabilityAnswer
    public let noise: NoiseAnswer
    public let wifiQuality: WifiQualityAnswer

    public init(
        laptopFriendlyToday: LaptopFriendlyAnswer,
        seatsAvailable: AvailabilityAnswer,
        outletsWorking: AvailabilityAnswer,
        noise: NoiseAnswer,
        wifiQuality: WifiQualityAnswer
    ) {
        self.laptopFriendlyToday = laptopFriendlyToday
        self.seatsAvailable = seatsAvailable
        self.outletsWorking = outletsWorking
        self.noise = noise
        self.wifiQuality = wifiQuality
    }
}

/// Request body for `POST /v1/venues/:id/observations`. `observedAt` is
/// deliberately omitted — the engine defaults it to server time, and the app
/// submits at the moment of observation anyway.
struct VenueObservationRequest: Encodable {
    let submittedBy: String
    let answers: ObservationAnswers
}

/// Seam for submitting a structured observation. `VenueAPI` is the real
/// implementation; `ScenarioVenueService` the deterministic stand-in; tests
/// add mocks. `submittedBy` v1 is an opaque non-empty token the engine does
/// NOT verify against any account system (401 only when missing/empty) —
/// real accounts arrive with brewdesk#48 without changing this shape.
public protocol VenueObservationSubmitting: Sendable {
    /// Returns the rescored venue from the engine's 201 response.
    @discardableResult
    func submitObservation(
        venueId: String,
        submittedBy: String,
        answers: ObservationAnswers
    ) async throws -> Venue
}
