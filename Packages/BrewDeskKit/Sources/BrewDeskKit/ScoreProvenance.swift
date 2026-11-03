import Foundation
import VenueKit

/// brewdesk#250: where a Work Fit number came from, read straight off the
/// venue's scored claims — so a 99 built from one visit report (the Moshava
/// Coffee post-mortem) reads as exactly that, and a 97 built from five
/// researched sources reads as that instead. Out of scope here: the number
/// itself and its label, both unchanged.
///
/// The five claims the engine scores (Wi-Fi, outlets, laptop policy, noise,
/// seating — the same set `Venue.isObserved` reads) fall into three buckets
/// by `Claim.source`:
///   - **visits** — `user_report`: a person was there and rated it. Counted
///     as DISTINCT observation dates, not claims: one report writes all
///     five claims with the same `observedAt`, and "Based on 5 visits" for
///     one rating is the very misread this line exists to prevent. Two
///     reports on the same calendar day collapse into one visit when the
///     engine sends date-only strings — the honest direction to be wrong
///     in (undercount, never overcount).
///   - **research** — everything else that isn't an estimate: `curated`,
///     `agent` (press research), `osm`, `field_visit`, `speed_test`,
///     `owner`, and any source this client doesn't recognize. Counted per
///     claim ("5 sources"), dated by the newest claim.
///   - **estimates** — `estimate`, plus any claim whose value is literally
///     "unknown" whatever its source says (the absence of an observation,
///     matching `Venue.isObserved`'s rule).
///
/// A pure value type — no SwiftUI — so the wording is unit-testable for all
/// four states (`ScoreProvenanceTests`); `ScoreProvenanceLine` in
/// `Components.swift` renders it.
struct ScoreProvenance: Equatable {
    /// Distinct `user_report` observation dates among the scored claims.
    let visitCount: Int
    /// Calendar day (UTC midnight, see `ProvenanceStamp.observationDate`)
    /// of the newest visit; `nil` when `visitCount == 0`.
    let newestVisit: Date?
    /// Non-estimate, non-visit scored claims.
    let researchCount: Int
    /// Calendar day of the newest research claim; `nil` when none.
    let newestResearch: Date?
    /// `estimate` claims plus "unknown"-valued ones.
    let estimateCount: Int

    init(attributes: VenueAttributes) {
        let scored: [Claim] = [
            attributes.wifi,
            attributes.outlets,
            attributes.laptopPolicy,
            attributes.noise,
            attributes.seating,
        ].compactMap { $0 }

        var visitDays: Set<String> = []
        var newestVisit: Date?
        var researchCount = 0
        var newestResearch: Date?
        var estimateCount = 0

        for claim in scored {
            if claim.isEstimate || claim.value == "unknown" {
                estimateCount += 1
            } else if claim.source == "user_report" {
                visitDays.insert(claim.observedAt)
                if let day = ProvenanceStamp.observationDate(of: claim) {
                    newestVisit = max(newestVisit ?? day, day)
                }
            } else {
                researchCount += 1
                if let day = ProvenanceStamp.observationDate(of: claim) {
                    newestResearch = max(newestResearch ?? day, day)
                }
            }
        }

        self.visitCount = visitDays.count
        self.newestVisit = newestVisit
        self.researchCount = researchCount
        self.newestResearch = newestResearch
        self.estimateCount = estimateCount
    }

    /// True when at least one visit or research claim stands behind the
    /// score. False means the score, if any, rests on estimates alone — the
    /// caller keeps today's "Not rated yet" copy and renders no line.
    var hasEvidence: Bool { visitCount > 0 || researchCount > 0 }

    // MARK: - Copy

    /// The detail-screen line under the Work Fit number — plain English, no
    /// field names:
    ///   - visits only: "Based on 1 visit · today"
    ///   - research only: "Researched Sep 16 · 5 sources"
    ///   - research and visits: "Researched Sep 16 · 1 visit"
    ///   - estimates only: `nil` — "Not rated yet" stays as it is.
    /// `now` and `locale` are injectable so the tests can pin "today".
    func detailLine(
        now: Date = .now,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String? {
        if researchCount > 0, let newestResearch {
            let when = Self.relativeDay(newestResearch, now: now, locale: locale, timeZone: timeZone)
            let evidence = visitCount > 0 ? Self.visitsPhrase(visitCount) : Self.sourcesPhrase(researchCount)
            return String(
                format: String(localized: "Researched %1$@ · %2$@"),
                locale: locale,
                when, evidence
            )
        }
        if visitCount > 0, let newestVisit {
            let when = Self.relativeDay(newestVisit, now: now, locale: locale, timeZone: timeZone)
            return String(
                format: String(localized: "Based on %1$@ · %2$@"),
                locale: locale,
                Self.visitsPhrase(visitCount), when
            )
        }
        return nil
    }

    /// The shelf/list-card form, short enough for the card's caption column:
    /// "1 visit" / "3 visits" when anyone has been there, "Researched" when
    /// the number rests on research alone, `nil` for estimates only.
    /// Visits win over research because a visit is the rarer, stronger
    /// signal and the card has room for one word.
    var compactLine: String? {
        if visitCount > 0 { return Self.visitsPhrase(visitCount) }
        if researchCount > 0 { return String(localized: "Researched") }
        return nil
    }

    /// SF Symbol for the line's leading glyph — a person for a visit, a
    /// magnifier for research. The glyph never carries the meaning alone
    /// (the words do), it just anchors the caption the way
    /// `ProvenanceStamp`'s seal/clock does.
    var symbolName: String {
        visitCount > 0 ? "person.fill.checkmark" : "doc.text.magnifyingglass"
    }

    static func visitsPhrase(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 visit")
            : String(format: String(localized: "%lld visits"), locale: .current, count)
    }

    static func sourcesPhrase(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 source")
            : String(format: String(localized: "%lld sources"), locale: .current, count)
    }

    /// "today" / "yesterday" for the two most recent calendar days, else
    /// the abbreviated month-day ("Sep 16") via `ProvenanceStamp.dayStyle`,
    /// which pins UTC so the day never rolls back west of Greenwich
    /// (brewdesk#142).
    ///
    /// `day` is a calendar date parsed at UTC midnight; "today" is decided
    /// against the DEVICE's calendar day in `timeZone`, re-expressed at UTC
    /// midnight so the two compare like for like. A `day` in the future
    /// (clock skew) reads as "today" rather than printing a nonsense gap.
    static func relativeDay(
        _ day: Date,
        now: Date,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let todayComponents = local.dateComponents([.year, .month, .day], from: now)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let today = utc.date(from: todayComponents) ?? now
        let daysAgo = utc.dateComponents([.day], from: day, to: today).day ?? 0
        switch daysAgo {
        case ...0: return String(localized: "today")
        case 1: return String(localized: "yesterday")
        default: return day.formatted(ProvenanceStamp.dayStyle(month: .abbreviated, locale: locale))
        }
    }
}
