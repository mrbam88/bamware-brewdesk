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

    /// bd#241 `numColor:"auto"` against the lime dark-map ramp (spec:
    /// "Numbers near-black (#06120D) on all four"): every tier's dark-map
    /// fill is bright enough that `auto` never needs bd#212's old "darkest
    /// fill gets a light number" exception.
    @Test func darkMapMarkerNumberIsAlwaysNearBlack() {
        for score in tierScores {
            let resolved = rgb(BrewDeskPalette.markerNumberColor(score: score), style: .dark)
            #expect(resolved.r < 0.06 && resolved.g < 0.10 && resolved.b < 0.08, "score \(score) dark-map number must be near-black #06120D, got \(resolved)")
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

    /// bd#241 rim `"light"` (Bilal's round-3 selection): replaces bd#221's
    /// per-tier "tint of the marker's own fill" outright with a single flat
    /// WHITE rim on BOTH maps — still strictly brighter than every tier's
    /// fill (white is lighter than any fill this ramp can produce), so this
    /// invariant stays meaningful even though the rim itself is no longer
    /// tier-dependent.
    @Test func markerRimIsLighterThanItsOwnFillInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for score in tierScores {
                let fillLuminance = relativeLuminance(UIColor(BrewDeskPalette.markerFill(score: score)).resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))
                let rimLuminance = relativeLuminance(UIColor(BrewDeskPalette.markerRim(score: score)).resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))
                #expect(rimLuminance > fillLuminance, "\(style == .light ? "light" : "dark") map score \(score): rim (\(rimLuminance)) must be lighter than its own fill (\(fillLuminance))")
            }
        }
    }

    @Test func markerRimIsSingleHueInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let hues = tierScores.map { hueDegrees(rgb(BrewDeskPalette.markerRim(score: $0), style: style)) }
            let spread = (hues.max() ?? 0) - (hues.min() ?? 0)
            #expect(spread < 15, "\(style == .light ? "light" : "dark") map rim ramp hue spread \(spread)° — must read as one hue family, mixed toward white only")
        }
    }

    /// bd#241: the rim is now a FIXED white at 92% opacity, identical on
    /// both maps and every tier — pins the exact value (`rgba(255,255,255,
    /// 0.92)`) so a future edit can't silently drift it back toward a
    /// per-tier tint.
    @Test func markerRimIsFlatWhiteNinetyTwoPercentOpacityOnBothMaps() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for score in tierScores {
                let resolved = UIColor(BrewDeskPalette.markerRim(score: score)).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
                #expect(r > 0.99 && g > 0.99 && b > 0.99, "\(style == .light ? "light" : "dark") map score \(score) rim RGB \((r, g, b)) is not pure white")
                #expect(abs(a - 0.92) < 0.01, "\(style == .light ? "light" : "dark") map score \(score) rim alpha \(a) is not 0.92")
            }
        }
    }

    /// bd#241 (Bilal's round-3 pin selection, `fill:"lime"`): the sage/mint
    /// dark-map ramp (`#86D6B0/#98E4C0/#ADF0D0/#C7F8E0`, bd#227's
    /// brighter-than-mock values) is replaced outright by a single-hue LIME
    /// ramp, matching the design-review page's `FILLS.lime` exactly. Pins
    /// the exact new per-tier hex so a future edit can't silently drift.
    @Test func darkMapMarkerFillMatchesTheLimeRampExactly() {
        // (score, expected 0xRRGGBB)
        let expected: [(Int, UInt32)] = [
            (40, 0x8FD214), // <60
            (65, 0xA3E61F), // 60-69
            (75, 0xB6F52A), // 70-79
            (90, 0xC9FF3D), // >=80
        ]
        for (score, want) in expected {
            let resolved = UIColor(BrewDeskPalette.markerFill(score: score)).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
            let wr = Double((want & 0xFF0000) >> 16) / 255
            let wg = Double((want & 0x00FF00) >> 8) / 255
            let wb = Double(want & 0x0000FF) / 255
            #expect(abs(Double(r) - wr) < 0.004 && abs(Double(g) - wg) < 0.004 && abs(Double(b) - wb) < 0.004,
                    "score \(score) dark-map fill \((r, g, b)) does not match #\(String(format: "%06X", want))")
        }
    }

    /// bd#241 (spec: "labels match the pins" — the dark map's café-name
    /// label now uses the >=80 lime tint, `markerFillDarkMap[3]`, exactly).
    /// Light map is unchanged.
    @Test func markerLabelTextMatchesTheTopDarkMapTierAndTheOriginalLightValue() {
        let darkResolved = UIColor(BrewDeskPalette.markerLabelText).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var dr: CGFloat = 0, dg: CGFloat = 0, db: CGFloat = 0, da: CGFloat = 0
        darkResolved.getRed(&dr, green: &dg, blue: &db, alpha: &da)
        // #C9FF3D
        #expect(abs(Double(dr) - 201.0 / 255) < 0.004 && abs(Double(dg) - 1.0) < 0.004 && abs(Double(db) - 61.0 / 255) < 0.004,
                "dark map label \((dr, dg, db)) does not match the >=80 lime tier #C9FF3D")

        let lightResolved = UIColor(BrewDeskPalette.markerLabelText).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        lightResolved.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        // #1C5243, unchanged from bd#221
        #expect(abs(Double(lr) - 28.0 / 255) < 0.004 && abs(Double(lg) - 82.0 / 255) < 0.004 && abs(Double(lb) - 67.0 / 255) < 0.004,
                "light map label \((lr, lg, lb)) does not match #1C5243")
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
