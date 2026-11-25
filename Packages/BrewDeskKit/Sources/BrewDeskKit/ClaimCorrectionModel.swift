// Single-claim correction — state machine + refresh (brewdesk#251).
// "Time limited" when laptops are fine: the user corrects that one line from
// the venue detail instead of redoing the five-question rating. A correction
// IS an observation with exactly one answer — same endpoint, same service
// seam, same auth rules as `ObservationFormModel`.
import Foundation
import SwiftUI
import VenueKit

/// A Workability claim the user can correct on its own. Each case knows the
/// question the full rating form asks for it and which engine claim it lands
/// on, so the correction sheet and the form can never drift apart.
public enum CorrectableClaim: String, CaseIterable, Identifiable, Sendable {
    case wifi, outlets, laptopPolicy, noise, seating

    public var id: String { rawValue }

    /// The claim this correction rewrites, as the venue currently shows it.
    /// `seating` is optional-first on the wire, so it can be absent.
    public func claim(in attributes: VenueAttributes) -> Claim? {
        switch self {
        case .wifi: attributes.wifi
        case .outlets: attributes.outlets
        case .laptopPolicy: attributes.laptopPolicy
        case .noise: attributes.noise
        case .seating: attributes.seating
        }
    }
}

extension ClaimCorrection {
    /// Which claim this answer corrects.
    public var claim: CorrectableClaim {
        switch self {
        case .laptopFriendlyToday: .laptopPolicy
        case .seatsAvailable: .seating
        case .outletsWorking: .outlets
        case .noise: .noise
        case .wifiQuality: .wifi
        }
    }
}

/// Drives the one-question correction sheet: pick → submit → submitted, with
/// the same friendly failed state (Retry re-submits the same pick) and the
/// same sign-in detour as the five-question form. All transition rules live
/// here so they are unit-testable without UI.
@Observable
public final class ClaimCorrectionModel {
    public enum Phase: Equatable {
        case editing
        case submitting
        /// `message` is the friendly, user-facing sentence — never a raw error.
        case failed(message: String)
        case submitted
        /// A session exists but no token could be produced, or the engine
        /// answered 401 after a forced refresh (`VenueAPIError
        /// .authenticationRequired`). The pick is untouched; the UI presents
        /// sign-in and calls `submit()` again once signed in.
        case signInRequired
    }

    public let venueId: String
    public let claim: CorrectableClaim
    public private(set) var selection: ClaimCorrection?
    public private(set) var phase: Phase = .editing
    /// The engine's response to a successful correction — what the detail
    /// screen refreshes its claims from. Nil until `phase == .submitted`.
    public private(set) var updatedVenue: Venue?

    private let service: any VenueObservationSubmitting
    private let submittedBy: String

    public init(
        venueId: String,
        claim: CorrectableClaim,
        service: any VenueObservationSubmitting,
        submittedBy: String = ObservationSubmitterIdentity.submitterID()
    ) {
        self.venueId = venueId
        self.claim = claim
        self.service = service
        self.submittedBy = submittedBy
    }

    public var isSubmitting: Bool { phase == .submitting }

    public var canSubmit: Bool {
        selection != nil && phase != .submitting && phase != .submitted
    }

    /// Picks the corrected value. An answer for a different claim than this
    /// sheet's is ignored — one sheet corrects one claim. Re-picking while
    /// failed returns to editing so a stale error never outlives a changed
    /// answer (same rule as the form).
    public func select(_ correction: ClaimCorrection) {
        guard correction.claim == claim else { return }
        switch phase {
        case .submitting, .submitted: return
        case .failed, .signInRequired: phase = .editing
        case .editing: break
        }
        selection = correction
    }

    /// No-op without a pick, while a submit is in flight, or after success.
    /// Sends exactly one answer. Failure keeps the pick — Retry is this
    /// same method.
    public func submit() async {
        guard let selection, canSubmit else { return }
        phase = .submitting
        do {
            updatedVenue = try await service.submitObservation(
                venueId: venueId,
                submittedBy: submittedBy,
                answers: ObservationAnswers(only: selection)
            )
            phase = .submitted
        } catch VenueAPIError.authenticationRequired {
            phase = .signInRequired
        } catch {
            phase = .failed(message: ObservationFormModel.friendlyMessage(for: error))
        }
    }

    /// Dismissing the sign-in sheet without signing in returns to editing
    /// with the pick intact. A no-op from any other phase.
    public func cancelSignInPrompt() {
        guard phase == .signInRequired else { return }
        phase = .editing
    }
}

// MARK: - Detail refresh

extension Venue {
    /// This venue with the claims and score the engine returned for a
    /// correction. Only what an observation can change is taken from
    /// `response` (claims, score, score honesty fields, last-verified stamp);
    /// everything the write response does not carry the way the detail
    /// payload does — hours, website, phone, press links, distance — is kept
    /// from `self`, so a correction never blanks the Info card.
    func applyingEngineClaims(from response: Venue) -> Venue {
        guard response.id == id else { return self }
        return Venue(
            id: id, name: name, lat: lat, lng: lng, address: address,
            neighborhood: neighborhood, borough: borough, hoursRaw: hoursRaw,
            vertical: vertical,
            attributes: response.attributes,
            vibeTags: vibeTags,
            workScore: response.workScore,
            lastVerified: response.lastVerified ?? lastVerified,
            distanceM: distanceM, venueType: venueType, website: website, phone: phone,
            email: email, tier: tier, news: news,
            scoreDisplay: response.scoreDisplay,
            scoreCoverage: response.scoreCoverage ?? scoreCoverage,
            scoreConfidence: response.scoreConfidence ?? scoreConfidence,
            // A pick is a label on the venue, not a claim: a correction
            // never removes it.
            pick: response.pick ?? pick
        )
    }
}

/// The engine's answers to this session's corrections, keyed by venue.
///
/// The detail screen is handed its `Venue` by whichever surface opened it
/// (map, saved, ask), and those keep their own copy until their next fetch.
/// Without this, a corrected row would snap back to the old value the moment
/// the detail sheet is reopened. The ledger is in-memory only and yields as
/// soon as the caller's copy is at least as fresh as the correction.
@MainActor
@Observable
public final class ClaimCorrectionLedger {
    public static let shared = ClaimCorrectionLedger()

    private var responses: [String: Venue] = [:]

    public init() {}

    /// Records the engine's response to a successful correction.
    public func record(_ response: Venue) {
        responses[response.id] = response
    }

    /// `venue` with any newer corrected claims applied.
    public func current(_ venue: Venue) -> Venue {
        guard let response = responses[venue.id],
              let correctedAt = response.lastVerified,
              (venue.lastVerified ?? "") < correctedAt
        else { return venue }
        return venue.applyingEngineClaims(from: response)
    }
}
