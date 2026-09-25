import SwiftUI
import Testing
import UIKit
@testable import BrewDeskKit
import VenueKit

/// brewdesk#240 — badge presence per type on the shelf card/list row/detail
/// header/map pin, verified as snapshot-free assertions on the exact logic
/// each surface renders from (`VenueTypeBadge.showsBadge` drives
/// `VenueTypeBadgeView`'s own `if`; `accessibilityTypeSuffix` drives what
/// `DiscoveryShelfCard`/`CafeListScreen`'s COMBINED VoiceOver label
/// announces, since `.accessibilityElement(children: .combine)` +  an
/// explicit `.accessibilityLabel(...)` would otherwise swallow
/// `VenueTypeBadgeView`'s own label). Contrast is verified numerically,
/// matching `ScoreBadgeContrastTests`' own approach for this codebase.
struct VenueTypeBadgeViewTests {
    // MARK: - Presence per type (card/row/detail/pin all read `showsBadge`)

    @Test func badgeIsHiddenForCafeAndUnknownVisibleForEveryOtherType() {
        #expect(VenueTypeBadge.cafe.showsBadge == false, "cafés are the default — no badge")
        #expect(VenueTypeBadge.unknown.showsBadge == false, "no real evidence to badge with")
        #expect(VenueTypeBadge.library.showsBadge)
        #expect(VenueTypeBadge.park.showsBadge)
        #expect(VenueTypeBadge.coworking.showsBadge)
    }

    // MARK: - The combined-label suffix (shelf card + list row)

    @Test func accessibilitySuffixIsEmptyForCafeAndUnknown() {
        #expect(accessibilityTypeSuffix(.cafe) == "")
        #expect(accessibilityTypeSuffix(.unknown) == "")
    }

    @Test func accessibilitySuffixNamesTheTypeForEveryBadgedCase() {
        #expect(accessibilityTypeSuffix(.library) == ", Library")
        #expect(accessibilityTypeSuffix(.park) == ", Park")
        #expect(accessibilityTypeSuffix(.coworking) == ", Coworking")
    }

    // MARK: - Contrast (BrewDeskPalette neutrals only, ≥4.5:1 both appearances)

    private func relativeLuminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func linearize(_ channel: CGFloat) -> Double {
            let c = Double(channel)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    private func contrastRatio(_ a: Color, _ b: Color, style: UIUserInterfaceStyle) -> Double {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let resolvedA = UIColor(a).resolvedColor(with: traits)
        let resolvedB = UIColor(b).resolvedColor(with: traits)
        let lighter = max(relativeLuminance(resolvedA), relativeLuminance(resolvedB))
        let darker = min(relativeLuminance(resolvedA), relativeLuminance(resolvedB))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// `VenueTypeBadgeView` uses `secondaryText` on `surfaceSecondary` — the
    /// same pair `ScoreBadgeContrastTests.estimateTagText...` already proves
    /// clears 3:1; the badge's caption2-weight-semibold text is still small
    /// text, but this checks the stricter 4.5:1 bar the ticket asks for,
    /// same requirement `ScoreBadgeContrastTests` holds the score tile to.
    @Test func badgeTextMeetsFourPointFiveToOneInLightMode() {
        let ratio = contrastRatio(BrewDeskPalette.secondaryText, BrewDeskPalette.surfaceSecondary, style: .light)
        #expect(ratio >= 4.5, "type badge text vs. fill (light): \(ratio):1")
    }

    @Test func badgeTextMeetsFourPointFiveToOneInDarkMode() {
        let ratio = contrastRatio(BrewDeskPalette.secondaryText, BrewDeskPalette.surfaceSecondary, style: .dark)
        #expect(ratio >= 4.5, "type badge text vs. fill (dark): \(ratio):1")
    }

    // MARK: - Coverage caption ("Based on N of 5 details")

    @Test func coverageCaptionIsNilWhenServerSendsNoCoverage() {
        #expect(scoreCoverageCaption(nil) == nil)
    }

    @Test func coverageCaptionNamesKnownOfTotal() {
        let coverage = ScoreCoverage(known: 1, of: 5, weight: 0.2, attributes: ["wifi"])
        #expect(scoreCoverageCaption(coverage) == "Based on 1 of 5 details")
    }

    @Test func coverageCaptionForFullEvidence() {
        let coverage = ScoreCoverage(known: 5, of: 5, weight: 1.0, attributes: ["wifi", "outlets", "laptopPolicy", "noise", "seating"])
        #expect(scoreCoverageCaption(coverage) == "Based on 5 of 5 details")
    }
}
