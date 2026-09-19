import Foundation

// Apple base-map café suggestions (brewdesk#182): when a tapped Apple POI
// label isn't one of our venues (`AppleFeatureMatcher`, no name+<60m match),
// the card offers "Suggest this café" — a discovery hint the engine could
// use to go research the place. Checked the existing wire surface first
// (`VenueAPI.swift`): `/v1/venues/:id/observations` and
// `VenueIntakeAPI`'s `/v1/venues/:id/photos` both require an EXISTING
// `venueId` — there is no "here's a place you don't have yet" route today.
//
// PROPOSED ENGINE CONTRACT (for the follow-up venue-engine ticket):
//   POST /v1/discovery-hints
//   body: { name: string, lat: number, lng: number, source: "apple-maps" }
//   → 201 { ok: true }; same zod .strict() convention as /observations.
// When that ships, an `EngineCafeSuggestionClient: CafeSuggesting` posts
// here; nothing above this seam (the card, its tests) changes.
//
// Constraint (bd#182 ticket): never persist Apple's own result data to disk
// or server. A suggestion is USER-INITIATED (a tap on "Suggest this café")
// and carries only name/lat/lng — never a cached catalog of Apple POIs —
// but even that goes straight out over the wire with no local spool. Unlike
// `ReportSpool` (`ReportBlockStore.swift`), the stub below holds nothing:
// there is nowhere durable it is allowed to keep an Apple-derived record
// while no endpoint exists.
public struct CafeSuggestion: Equatable, Sendable {
    public let name: String
    public let lat: Double
    public let lng: Double
    public let source: String

    public init(name: String, lat: Double, lng: Double, source: String = "apple-maps") {
        self.name = name
        self.lat = lat
        self.lng = lng
        self.source = source
    }
}

/// Seam for the suggestion action. UI and tests depend on this, not on any
/// concrete transport (see the proposed engine contract above).
public protocol CafeSuggesting: Sendable {
    func suggestCafe(_ suggestion: CafeSuggestion) async throws
}

/// TODO(brewdesk#182): replace with a real `VenueAPI`-style client once
/// bamware-venue-engine ships `POST /v1/discovery-hints` (see the proposed
/// contract above). Until then this is an explicit, documented no-op — never
/// a silent success dressed up as one: it exists so the "Suggest this café"
/// button has somewhere safe to call rather than nothing at all, and so the
/// UI's "sent" state is exercised by tests without inventing a fake wire
/// call. Holds no state, persists nothing.
public struct NullCafeSuggestionClient: CafeSuggesting {
    public init() {}

    public func suggestCafe(_ suggestion: CafeSuggestion) async throws {
        // Intentionally empty — see the TODO above.
    }
}
