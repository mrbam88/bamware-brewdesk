import SwiftUI
import Testing
import UIKit
@testable import BrewDeskKit

/// bd#212: the micro-teardrop marker palette — single hue, lightness-only,
/// with the ramp DIRECTION flipped by map appearance (dark basemap: best
/// score is brightest; light basemap: best score is darkest/most
/// saturated). Founder is red-green colorblind, so hue must never carry the
/// signal in either appearance — verified numerically here against the
/// ACTUAL resolved colors, the same approach `ScoreBadgeContrastTests`
/// established for the old cluster-era dot palette this replaces.
struct MarkerPaletteTests {
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
        let luminanceA = relativeLuminance(resolvedA)
        let luminanceB = relativeLuminance(resolvedB)
        let lighter = max(luminanceA, luminanceB)
        let darker = min(luminanceA, luminanceB)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func rgb(_ color: Color, style: UIUserInterfaceStyle) -> (r: Double, g: Double, b: Double) {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

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

    /// Representative scores for the four tier buckets (`<60`, `60-69`,
    /// `70-79`, `>=80`) — matches `BrewDeskPalette.markerTierIndex`.
    private let tierScores = [40, 65, 75, 90]

    @Test func markerFillIsSingleHueInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let hues = tierScores.map { hueDegrees(rgb(BrewDeskPalette.markerFill(score: $0), style: style)) }
            let spread = (hues.max() ?? 0) - (hues.min() ?? 0)
            #expect(spread < 15, "\(style == .light ? "light" : "dark") map marker ramp hue spread \(spread)° — must read as one hue family")
        }
    }

    @Test func darkMapMarkerFillIsBrightestForTheBestScore() {
        let luminances = tierScores.map { relativeLuminance(UIColor(BrewDeskPalette.markerFill(score: $0)).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))) }
        for i in 1..<luminances.count {
            #expect(luminances[i] > luminances[i - 1], "dark map: lightness must strictly increase with score, got \(luminances)")
        }
    }

    @Test func lightMapMarkerFillIsDarkestForTheBestScore() {
        // bd#217: white numbers on every light-map tier needed the fill
        // ramp to hold >=4.5:1 everywhere, which collapsed it to the
        // spec's "at most three lightness steps" — the two lowest tiers
        // (`<60`, `60-69`) now share the lightest step, so lightness is
        // monotonic NON-increasing with score rather than strictly
        // decreasing at every step. It must still never go the wrong way
        // (a worse score getting a DARKER fill than a better one).
        let luminances = tierScores.map { relativeLuminance(UIColor(BrewDeskPalette.markerFill(score: $0)).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))) }
        for i in 1..<luminances.count {
            #expect(luminances[i] <= luminances[i - 1], "light map: lightness must never INCREASE with score (best = darkest/most saturated), got \(luminances)")
        }
        #expect(Set(luminances).count <= 3, "light map fill must use at most three lightness steps (bd#217 spec)")
        #expect(luminances.last! < luminances.first!, "the best and worst tiers must still be visibly different")
    }

    /// bd#217 (TestFlight build 26 feedback — "change the color of the
    /// text to white on the pins"): every light-map tier's number is now
    /// pure white, replacing the old split (dark number on the two
    /// lighter tiers) that read as low-contrast dark-green-on-sage.
    @Test func lightMapMarkerNumberIsAlwaysWhite() {
        for score in tierScores {
            let resolved = rgb(BrewDeskPalette.markerNumberColor(score: score), style: .light)
            #expect(resolved.r > 0.98 && resolved.g > 0.98 && resolved.b > 0.98, "score \(score) light-map number must be white, got \(resolved)")
        }
    }

    @Test func markerNumberColorClearsContrastAgainstItsOwnFillInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for score in tierScores {
                let ratio = contrastRatio(
                    BrewDeskPalette.markerNumberColor(score: score),
                    BrewDeskPalette.markerFill(score: score),
                    style: style
                )
                #expect(ratio >= 4.5, "\(style == .light ? "light" : "dark") map score \(score) number-vs-fill contrast only \(ratio):1")
            }
        }
    }

    /// bd#217 (Bilal, same PR as the white-number fix): "the border...
    /// should be white instead of dark — on the pins" for the LIGHT map;
    /// DARK keeps the bd#212 dark-hairline-plus-shadow pairing exactly as
    /// shipped (his own earlier choice on the dark mock).
    @Test func markerHairlineIsWhiteInLightMapAndStaysDarkInDarkMap() {
        let resolvedLight = UIColor(BrewDeskPalette.markerHairline).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let resolvedDark = UIColor(BrewDeskPalette.markerHairline).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(relativeLuminance(resolvedLight) > 0.85, "light map hairline must read as a near-white edge (bd#217)")
        #expect(relativeLuminance(resolvedDark) < 0.05, "dark map hairline must stay a dark edge, unchanged from bd#212")
    }

    @Test func speckFillIsNeutralNeverTierColored() {
        // A speck's fill must not shift hue with score — it isn't even
        // score-driven (unrated venues have no score to color by), but this
        // also guards against ever accidentally wiring `markerFill` into
        // the speck path.
        let light = rgb(BrewDeskPalette.markerSpeckFill, style: .light)
        let dark = rgb(BrewDeskPalette.markerSpeckFill, style: .dark)
        // Achromatic (r≈g≈b) within a small tolerance — never a saturated
        // green like the rated ramp.
        #expect(abs(light.r - light.g) < 0.03 && abs(light.g - light.b) < 0.03)
        #expect(abs(dark.r - dark.g) < 0.03 && abs(dark.g - dark.b) < 0.03)
    }
}
