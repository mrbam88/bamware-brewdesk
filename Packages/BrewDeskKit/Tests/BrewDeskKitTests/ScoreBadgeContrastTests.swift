import SwiftUI
import Testing
import UIKit
@testable import BrewDeskKit

/// bd#209: the shelf card's score tile ("84 WORK FIT") used to print the
/// tier color itself as TEXT on a light tint of that same color — on
/// `great` (a dark green) that rendered as dark-green-on-dark-green,
/// unreadable, and worse for a red-green colorblind reader since the only
/// thing separating the number from its tile was that exact hue-on-hue
/// mismatch. `ScoreBadge` (used on the list row and the detail screen) had
/// the same shape of bug for the `good` tier specifically: fixed white text
/// only reaches ~3.35:1 against that tier's sage fill, under the 4.5:1 bar.
///
/// Both were fixed the same way: a neutral, appearance-adaptive tile
/// (`surfaceSecondary` background, `clusterSurfaceText` label) with the
/// tier color moved to a ring instead of doubling as the text color. This
/// verifies that fix numerically — WCAG 2.1 contrast math against the
/// ACTUAL resolved colors in both appearances — rather than trusting the
/// design record's own comments.
struct ScoreBadgeContrastTests {
    private func relativeLuminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func linearize(_ channel: CGFloat) -> Double {
            let c = Double(channel)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    /// WCAG 2.1 contrast ratio between two `Color`s as resolved for a given
    /// appearance — 1:1 (no contrast) to 21:1 (black on white).
    private func contrastRatio(_ a: Color, _ b: Color, style: UIUserInterfaceStyle) -> Double {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let resolvedA = UIColor(a).resolvedColor(with: traits)
        let resolvedB = UIColor(b).resolvedColor(with: traits)
        let luminanceA = relativeLuminance(resolvedA)
        let luminanceB = relativeLuminance(resolvedB)
        let lighter = max(luminanceA, luminanceB)
        let darker = min(luminanceA, luminanceB)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// The badge number ("84") needs ≥4.5:1 (normal-size text). Same token
    /// also renders "WORK FIT" (a caption, needing only ≥3:1), so clearing
    /// the stricter bar covers both.
    @Test func scoreBadgeTextMeetsFourPointFiveToOneInLightMode() {
        let ratio = contrastRatio(BrewDeskPalette.clusterSurfaceText, BrewDeskPalette.surfaceSecondary, style: .light)
        #expect(ratio >= 4.5, "score badge text vs. tile background (light): \(ratio):1")
    }

    @Test func scoreBadgeTextMeetsFourPointFiveToOneInDarkMode() {
        let ratio = contrastRatio(BrewDeskPalette.clusterSurfaceText, BrewDeskPalette.surfaceSecondary, style: .dark)
        #expect(ratio >= 4.5, "score badge text vs. tile background (dark): \(ratio):1")
    }

    /// Regression guard for the exact bug report: fixed white text on the
    /// `good` tier's raw fill color falls short of 4.5:1 — documenting why
    /// `ScoreBadge`/`DiscoveryShelfCard` no longer use the tier color as a
    /// text color at all.
    @Test func whiteTextOnTheGoodTierFillAloneWouldHaveFailedNormalTextContrast() {
        let ratio = contrastRatio(.white, BrewDeskPalette.moss, style: .light)
        #expect(ratio < 4.5, "if this ever passes, the badge redesign's rationale (bd#209) needs re-checking")
    }
}
