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

    // MARK: - bd#211: observed dot palette — single hue, lightness-ordered

    private func rgb(_ color: Color, style: UIUserInterfaceStyle) -> (r: Double, g: Double, b: Double) {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    /// Hue in degrees (0..<360), HSL convention — 0 undefined (achromatic)
    /// components report 0, which never happens for the saturated brand
    /// green this palette uses.
    private func hueDegrees(_ c: (r: Double, g: Double, b: Double)) -> Double {
        let maxC = max(c.r, c.g, c.b)
        let minC = min(c.r, c.g, c.b)
        let delta = maxC - minC
        guard delta > 0 else { return 0 }
        var hue: Double
        if maxC == c.r {
            hue = 60 * (((c.g - c.b) / delta).truncatingRemainder(dividingBy: 6))
        } else if maxC == c.g {
            hue = 60 * (((c.b - c.r) / delta) + 2)
        } else {
            hue = 60 * (((c.r - c.g) / delta) + 4)
        }
        if hue < 0 { hue += 360 }
        return hue
    }

    /// bd#211: the whole point of the redesign — observed dots used to tint
    /// by `ScoreTier.color` (four different hues), which a red-green
    /// colorblind viewer can't reliably read on a marker with no number.
    /// Every step of the new ramp must share ONE hue family (brand green,
    /// spread under 15°) in BOTH appearances, and lightness must strictly
    /// increase from `great` (darkest/most saturated) to `weak`/`mixed`
    /// (lightest) — tier is legible by lightness alone.
    @Test func observedDotPaletteIsSingleHueAndLightnessOrdered() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let steps = [
                BrewDeskPalette.observedDotGreat,
                BrewDeskPalette.observedDotGood,
                BrewDeskPalette.observedDotWeak,
            ].map { rgb($0, style: style) }

            let hues = steps.map(hueDegrees)
            let spread = (hues.max() ?? 0) - (hues.min() ?? 0)
            #expect(spread < 15, "\(style == .light ? "light" : "dark") mode dot palette hue spread \(spread)° — must read as one hue family")

            let luminances = steps.map { c in
                relativeLuminance(UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1))
            }
            #expect(
                luminances[0] < luminances[1] && luminances[1] < luminances[2],
                "\(style == .light ? "light" : "dark") mode dot palette must be strictly lightness-ordered great < good < weak, got \(luminances)"
            )

            // Each step must clear the ticket's own >=1.6:1 adjacent-step bar.
            for i in 1..<luminances.count {
                let ratio = (luminances[i] + 0.05) / (luminances[i - 1] + 0.05)
                #expect(ratio >= 1.6, "\(style == .light ? "light" : "dark") mode step \(i) only \(ratio):1 from its neighbour, need >=1.6:1")
            }
        }
    }

    /// Every dot step should clear 3:1 against the app's own background in
    /// its own appearance — the best available proxy for "the map", since
    /// the real basemap's colors aren't something this package controls or
    /// can script against directly.
    @Test func observedDotPaletteClearsThreeToOneAgainstItsOwnAppearanceBackground() {
        let lightSteps: [Color] = [BrewDeskPalette.observedDotGreat, BrewDeskPalette.observedDotGood, BrewDeskPalette.observedDotWeak]
        for step in lightSteps {
            let ratio = contrastRatio(step, BrewDeskPalette.page, style: .light)
            #expect(ratio >= 3, "light mode dot step vs. page background: \(ratio):1")
        }
        for step in lightSteps {
            let ratio = contrastRatio(step, BrewDeskPalette.page, style: .dark)
            #expect(ratio >= 3, "dark mode dot step vs. page background: \(ratio):1")
        }
    }
}
