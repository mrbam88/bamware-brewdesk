import Foundation
import SwiftUI
import Testing
import UIKit
import VenueKit
@testable import BrewDeskKit

/// brewdesk#250: the provenance line under the Work Fit number must say, in
/// plain English, what the score rests on — and say nothing at all when it
/// rests on estimates alone, so "Not rated yet" is left exactly as it was.
/// The four states the ticket names (research only, one report, research +
/// reports, estimates only) are each pinned here as wording, and then
/// rendered once per appearance through `ImageRenderer` so a light/dark
/// regression in `ScoreProvenanceLine` fails a test, not a screenshot
/// review.
@Suite struct ScoreProvenanceTests {
    private let enUS = Locale(identifier: "en_US")
    private let utc = TimeZone(identifier: "UTC")!

    // MARK: - Fixtures

    private func claim(_ source: String, observedAt: String, value: String = "fast", confidence: Double = 0.8) -> Claim {
        Claim(value: value, source: source, confidence: confidence, observedAt: observedAt)
    }

    /// The engine's actual shape for a single visit report (Moshava Coffee,
    /// 2026-10-27): all five scored claims from one `user_report`, same day,
    /// plus an outdoor-seating estimate that is not scored at all.
    private func oneVisit(on day: String = "2026-10-27") -> VenueAttributes {
        VenueAttributes(
            wifi: claim("user_report", observedAt: day, confidence: 0.7),
            outlets: claim("user_report", observedAt: day, value: "plenty", confidence: 0.7),
            laptopPolicy: claim("user_report", observedAt: day, value: "unrestricted", confidence: 0.7),
            noise: claim("user_report", observedAt: day, value: "quiet", confidence: 0.7),
            seating: claim("user_report", observedAt: day, value: "some", confidence: 0.7),
            outdoorSeating: claim("estimate", observedAt: "2026-08-01", value: "unknown", confidence: 0)
        )
    }

    private func researched(on day: String = "2026-09-16") -> VenueAttributes {
        VenueAttributes(
            wifi: claim("curated", observedAt: day),
            outlets: claim("curated", observedAt: day, value: "plenty"),
            laptopPolicy: claim("curated", observedAt: day, value: "unrestricted"),
            noise: claim("agent", observedAt: day, value: "moderate", confidence: 0.6),
            seating: claim("curated", observedAt: day, value: "some")
        )
    }

    private func researchedPlusVisit() -> VenueAttributes {
        VenueAttributes(
            wifi: claim("user_report", observedAt: "2026-10-01", confidence: 0.7),
            outlets: claim("curated", observedAt: "2026-09-16", value: "plenty"),
            laptopPolicy: claim("curated", observedAt: "2026-09-16", value: "unrestricted"),
            noise: claim("user_report", observedAt: "2026-10-01", value: "quiet", confidence: 0.7),
            seating: claim("curated", observedAt: "2026-09-16", value: "some")
        )
    }

    private func estimatesOnly() -> VenueAttributes {
        VenueAttributes(
            wifi: claim("estimate", observedAt: "2026-08-01", value: "unknown", confidence: 0.3),
            outlets: claim("estimate", observedAt: "2026-08-01", value: "unknown", confidence: 0.3),
            laptopPolicy: claim("estimate", observedAt: "2026-08-01", value: "unknown", confidence: 0.3),
            noise: claim("estimate", observedAt: "2026-08-01", value: "unknown", confidence: 0.3),
            seating: claim("estimate", observedAt: "2026-08-01", value: "unknown", confidence: 0.3)
        )
    }

    private func venue(_ attributes: VenueAttributes, scoreDisplay: ScoreDisplay) -> Venue {
        Venue(
            id: "bd250", name: "Provenance Café", lat: 40.73, lng: -74.0, address: nil,
            neighborhood: "Greenwich Village", borough: "Manhattan", hoursRaw: nil, vertical: "cafe",
            attributes: attributes, vibeTags: [], workScore: 99, lastVerified: nil, distanceM: nil,
            scoreDisplay: scoreDisplay
        )
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    // MARK: - The four states

    @Test func oneVisitReadsAsOneVisitNotFiveClaims() {
        let provenance = ScoreProvenance(attributes: oneVisit())
        #expect(provenance.visitCount == 1)
        #expect(provenance.researchCount == 0)
        #expect(provenance.estimateCount == 0)
        #expect(provenance.hasEvidence)
        #expect(
            provenance.detailLine(now: date("2026-10-27T18:00:00Z"), locale: enUS, timeZone: utc)
                == "Based on 1 visit · today"
        )
        #expect(provenance.compactLine == "1 visit")
    }

    @Test func researchOnlyReadsResearchedDateAndSourceCount() {
        let provenance = ScoreProvenance(attributes: researched())
        #expect(provenance.visitCount == 0)
        #expect(provenance.researchCount == 5)
        #expect(
            provenance.detailLine(now: date("2026-11-03T12:00:00Z"), locale: enUS, timeZone: utc)
                == "Researched Sep 16 · 5 sources"
        )
        #expect(provenance.compactLine == "Researched")
    }

    @Test func researchPlusVisitLeadsWithTheVisit() {
        let provenance = ScoreProvenance(attributes: researchedPlusVisit())
        #expect(provenance.visitCount == 1)
        #expect(provenance.researchCount == 3)
        #expect(
            provenance.detailLine(now: date("2026-11-03T12:00:00Z"), locale: enUS, timeZone: utc)
                == "Researched Sep 16 · 1 visit"
        )
        #expect(provenance.compactLine == "1 visit")
    }

    @Test func estimatesOnlyHasNoLineSoNotRatedYetIsUnchanged() {
        let provenance = ScoreProvenance(attributes: estimatesOnly())
        #expect(provenance.visitCount == 0)
        #expect(provenance.researchCount == 0)
        #expect(provenance.estimateCount == 5)
        #expect(!provenance.hasEvidence)
        #expect(provenance.detailLine(now: date("2026-11-03T12:00:00Z"), locale: enUS, timeZone: utc) == nil)
        #expect(provenance.compactLine == nil)
    }

    // MARK: - Counting rules

    @Test func visitsAreDistinctDaysNotClaims() {
        var attributes = oneVisit(on: "2026-10-27")
        attributes = VenueAttributes(
            wifi: claim("user_report", observedAt: "2026-10-20", confidence: 0.7),
            outlets: attributes.outlets,
            laptopPolicy: attributes.laptopPolicy,
            noise: claim("user_report", observedAt: "2026-10-20", value: "quiet", confidence: 0.7),
            seating: attributes.seating
        )
        let provenance = ScoreProvenance(attributes: attributes)
        #expect(provenance.visitCount == 2)
        #expect(
            provenance.detailLine(now: date("2026-10-27T23:00:00Z"), locale: enUS, timeZone: utc)
                == "Based on 2 visits · today"
        )
        #expect(provenance.compactLine == "2 visits")
    }

    @Test func unknownValueCountsAsEstimateWhateverItsSourceSays() {
        var attributes = researched()
        attributes = VenueAttributes(
            wifi: claim("curated", observedAt: "2026-09-16", value: "unknown"),
            outlets: attributes.outlets,
            laptopPolicy: attributes.laptopPolicy,
            noise: attributes.noise,
            seating: attributes.seating
        )
        let provenance = ScoreProvenance(attributes: attributes)
        #expect(provenance.researchCount == 4)
        #expect(provenance.estimateCount == 1)
        #expect(
            provenance.detailLine(now: date("2026-11-03T12:00:00Z"), locale: enUS, timeZone: utc)
                == "Researched Sep 16 · 4 sources"
        )
    }

    @Test func unscoredOutdoorSeatingNeverCounts() {
        // `oneVisit()` carries an outdoor-seating estimate; the score never
        // read it, so neither does the line.
        #expect(ScoreProvenance(attributes: oneVisit()).estimateCount == 0)
    }

    @Test func singleResearchSourceIsSingular() {
        let attributes = VenueAttributes(
            wifi: claim("curated", observedAt: "2026-09-16"),
            outlets: claim("estimate", observedAt: "2026-08-01", value: "unknown", confidence: 0.3),
            laptopPolicy: claim("estimate", observedAt: "2026-08-01", value: "unknown", confidence: 0.3),
            noise: claim("estimate", observedAt: "2026-08-01", value: "unknown", confidence: 0.3)
        )
        #expect(
            ScoreProvenance(attributes: attributes)
                .detailLine(now: date("2026-11-03T12:00:00Z"), locale: enUS, timeZone: utc)
                == "Researched Sep 16 · 1 source"
        )
    }

    // MARK: - Dates

    @Test func visitDateReadsYesterdayThenTheDay() {
        let provenance = ScoreProvenance(attributes: oneVisit(on: "2026-10-27"))
        #expect(
            provenance.detailLine(now: date("2026-10-28T03:00:00Z"), locale: enUS, timeZone: utc)
                == "Based on 1 visit · yesterday"
        )
        #expect(
            provenance.detailLine(now: date("2026-11-03T12:00:00Z"), locale: enUS, timeZone: utc)
                == "Based on 1 visit · Oct 27"
        )
    }

    /// brewdesk#142's rule carried over: `observedAt` is a calendar day, so
    /// a New York evening on the 27th is still "today" for a report dated
    /// the 27th — the UTC-midnight parse must not roll it back a day.
    @Test func todayIsDecidedInTheDeviceTimeZone() {
        let provenance = ScoreProvenance(attributes: oneVisit(on: "2026-10-27"))
        let newYork = TimeZone(identifier: "America/New_York")!
        // 2026-10-28T02:00Z is still 2026-10-27 22:00 in New York.
        #expect(
            provenance.detailLine(now: date("2026-10-28T02:00:00Z"), locale: enUS, timeZone: newYork)
                == "Based on 1 visit · today"
        )
    }

    @Test func futureDatedReportReadsAsToday() {
        let provenance = ScoreProvenance(attributes: oneVisit(on: "2026-10-27"))
        #expect(
            provenance.detailLine(now: date("2026-10-26T12:00:00Z"), locale: enUS, timeZone: utc)
                == "Based on 1 visit · today"
        )
    }

    @Test func newestResearchDateWins() {
        let attributes = VenueAttributes(
            wifi: claim("curated", observedAt: "2026-05-01"),
            outlets: claim("curated", observedAt: "2026-09-16", value: "plenty"),
            laptopPolicy: claim("curated", observedAt: "2026-07-04", value: "unrestricted"),
            noise: claim("curated", observedAt: "2026-01-02", value: "moderate")
        )
        #expect(
            ScoreProvenance(attributes: attributes)
                .detailLine(now: date("2026-11-03T12:00:00Z"), locale: enUS, timeZone: utc)
                == "Researched Sep 16 · 4 sources"
        )
    }

    @Test func coverageSuffixIsShortFormOfTheCaption() {
        let coverage = ScoreCoverage(known: 3, of: 5, weight: 0.6, attributes: ["wifi", "outlets", "noise"])
        #expect(scoreCoverageSuffix(coverage) == "3 of 5 details")
        #expect(scoreCoverageCaption(coverage) == "Based on 3 of 5 details")
        #expect(scoreCoverageSuffix(nil) == nil)
    }

    // MARK: - Rendering, light and dark

    /// Renders the real view for each evidenced state in both appearances.
    /// Not a pixel snapshot (this package has no snapshot library) — it
    /// proves the view body resolves and lays out under each color scheme
    /// without tripping an isolation or token error, for the detail and
    /// compact forms alike.
    @Test(arguments: [ColorScheme.light, .dark])
    func lineRendersInBothAppearances(scheme: ColorScheme) throws {
        let states: [(String, VenueAttributes)] = [
            ("visit", oneVisit()),
            ("research", researched()),
            ("both", researchedPlusVisit()),
        ]
        for (name, attributes) in states {
            for compact in [false, true] {
                let view = ScoreProvenanceLine(venue: venue(attributes, scoreDisplay: .rated(99)), compact: compact)
                    .padding()
                    .background(BrewDeskPalette.surface)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try #require(renderer.uiImage, "\(name) compact=\(compact) \(scheme)")
                #expect(image.size.width > 40, "\(name) compact=\(compact) \(scheme) rendered too narrow")
                #expect(image.size.height > 10, "\(name) compact=\(compact) \(scheme) rendered too short")
            }
        }
    }

    /// The caption's token clears WCAG's 3:1 bar for small text on both
    /// surfaces it sits on (the detail hero's `foam`-tinted card and the
    /// shelf card's `surface`), in both appearances — the same numeric
    /// check `ScoreBadgeContrastTests` runs for the badge.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func captionTokenClearsContrastOnItsSurfaces(style: UIUserInterfaceStyle) {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let text = UIColor(BrewDeskPalette.secondaryText).resolvedColor(with: traits)
        for surface in [BrewDeskPalette.surface, BrewDeskPalette.page] {
            let background = UIColor(surface).resolvedColor(with: traits)
            #expect(Self.contrastRatio(text, background) >= 4.5, "\(style)")
        }
    }

    private static func contrastRatio(_ a: UIColor, _ b: UIColor) -> Double {
        func luminance(_ color: UIColor) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &alpha)
            func linearize(_ channel: CGFloat) -> Double {
                let c = Double(channel)
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
        }
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
