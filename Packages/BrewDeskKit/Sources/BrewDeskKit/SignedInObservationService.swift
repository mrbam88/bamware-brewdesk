import Foundation
import VenueKit

/// brewdesk#249: a signed-in rating must never go out anonymous.
///
/// `VenueAPI` attaches `Authorization: Bearer` only when its `tokenProvider`
/// hands back a token, and `BrewDeskAccountTenant.freshAccessToken` answers
/// `nil` both when there is no session *and* when the refresh failed. The
/// engine (venue-engine `communityAuth`) treats a missing header as an
/// anonymous submission, so a signed-in user whose refresh failed had their
/// visit rating recorded as `"anonymous"` with no warning (Moshava Coffee,
/// 2026-10-27). This wrapper closes that gap at the seam the form already
/// understands: when a session exists but no token can be produced, it
/// throws `VenueAPIError.authenticationRequired`, which
/// `ObservationFormModel` turns into the "Sign in to submit" sheet with the
/// draft intact. Signed-out submissions pass straight through unchanged.
struct SignedInObservationService: VenueObservationSubmitting {
    let hasSession: @Sendable () async -> Bool
    let accessToken: @Sendable () async -> String?
    let upstream: any VenueObservationSubmitting

    @discardableResult
    func submitObservation(
        venueId: String,
        submittedBy: String,
        answers: ObservationAnswers
    ) async throws -> Venue {
        if await hasSession(), await accessToken() == nil {
            throw VenueAPIError.authenticationRequired
        }
        return try await upstream.submitObservation(
            venueId: venueId,
            submittedBy: submittedBy,
            answers: answers
        )
    }
}
