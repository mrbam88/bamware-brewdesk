import Testing
import VenueKit
@testable import BrewDeskKit

/// brewdesk#216: the Workability card used to render an estimate's VALUE in
/// `clayText` (brick red) — unreadable as "unverified" vs. "bad" for a
/// red-green colorblind viewer, and misleading to everyone else (red reads
/// as an error even for a genuinely good value like "Unrestricted"). These
/// tests pin `ClaimValueStyle.classify(_:)`, the pure function `ClaimRow`
/// now drives its coloring/icon/tag from, so the mapping stays correct
/// without needing to render SwiftUI.
struct ClaimValueStyleTests {
    private func claim(
        value: String,
        source: String,
        confidence: Double = 0.8
    ) -> Claim {
        Claim(value: value, source: source, confidence: confidence, observedAt: "2026-08-01")
    }

    // MARK: - Verified / curated / user-reported → `.known`

    @Test func curatedValueIsKnown() {
        #expect(ClaimValueStyle.classify(claim(value: "unrestricted", source: "curated")) == .known)
    }

    @Test func userReportedValueIsKnown() {
        #expect(ClaimValueStyle.classify(claim(value: "fast", source: "user_report")) == .known)
    }

    @Test func fieldVisitValueIsKnown() {
        #expect(ClaimValueStyle.classify(claim(value: "plenty", source: "field_visit")) == .known)
    }

    @Test func osmValueIsKnown() {
        // OSM baseline claims are unverified data, but not an "estimate"
        // source — the card already says so via its own provenance stamp
        // ("OSM baseline · updated …"); the row's own value stays plain.
        #expect(ClaimValueStyle.classify(claim(value: "some", source: "osm")) == .known)
    }

    // MARK: - Estimate → `.unverified(showsEstimateTag: true)`

    @Test func estimateSourceShowsTheEstimateTag() {
        #expect(
            ClaimValueStyle.classify(claim(value: "unrestricted", source: "estimate"))
                == .unverified(showsEstimateTag: true)
        )
    }

    /// The evidence screenshot this ticket started from: an unrated café's
    /// laptop policy showed as a good-looking value ("Unrestricted") in
    /// brick red — exactly the "red doesn't mean bad" confusion this fixes.
    @Test func aGoodLookingEstimateStillGetsTheEstimateTagNotAColorAlone() {
        let style = ClaimValueStyle.classify(claim(value: "unrestricted", source: "estimate"))
        guard case .unverified(let showsTag) = style else {
            Issue.record("expected .unverified, got \(style)")
            return
        }
        #expect(showsTag)
    }

    // MARK: - Unknown value → `.unverified(showsEstimateTag: false)`, any source

    @Test func unknownValueIsUnverifiedWithNoTagEvenWhenEstimate() {
        #expect(
            ClaimValueStyle.classify(claim(value: "unknown", source: "estimate"))
                == .unverified(showsEstimateTag: false)
        )
    }

    @Test func unknownValueIsUnverifiedWithNoTagEvenFromAHumanSource() {
        // A human source can still report "unknown" for one attribute — the
        // word itself already says so, so no redundant "estimate" tag.
        #expect(
            ClaimValueStyle.classify(claim(value: "unknown", source: "curated"))
                == .unverified(showsEstimateTag: false)
        )
    }

    // MARK: - Genuinely negative KNOWN values → `.negativeKnown`

    @Test func discouragedFromANonEstimateSourceIsNegativeKnown() {
        #expect(ClaimValueStyle.classify(claim(value: "discouraged", source: "curated")) == .negativeKnown)
    }

    @Test func weekendBannedSingularSpellingIsNegativeKnown() {
        #expect(ClaimValueStyle.classify(claim(value: "weekend_banned", source: "field_visit")) == .negativeKnown)
    }

    @Test func weekendsBannedPluralSpellingIsNegativeKnown() {
        // ve#… wire inconsistency: `VenueFilter` matches the plural
        // `weekends_banned`; `localizedAttributeValue` renders the singular
        // `weekend_banned`. Both must classify as negative regardless.
        #expect(ClaimValueStyle.classify(claim(value: "weekends_banned", source: "curated")) == .negativeKnown)
    }

    /// A negative value from an ESTIMATE source stays in the unverified
    /// bucket (secondary text + tag) rather than the negative-known bucket
    /// (primary text + warning icon) — the estimate isn't confirmed evidence
    /// of a real restriction yet.
    @Test func discouragedFromAnEstimateSourceIsUnverifiedNotNegativeKnown() {
        #expect(
            ClaimValueStyle.classify(claim(value: "discouraged", source: "estimate"))
                == .unverified(showsEstimateTag: true)
        )
    }
}
