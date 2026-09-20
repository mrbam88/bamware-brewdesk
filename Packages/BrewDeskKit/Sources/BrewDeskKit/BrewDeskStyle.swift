import SwiftUI
import UIKit
import VenueKit

/// Warm Utilitarian (brewdesk#98): green/sand/sage system, replacing the
/// espresso/cream coffee palette. Every role below is a 9-step ramp from
/// near-black to near-white; the semantic aliases (`roast`, `oat`, `moss`, …)
/// pick one step per role so call sites keep referencing a stable name while
/// the underlying hue can move. Fill/pin tokens stay a single static value —
/// they always sit behind fixed white text (badges, map pins) so they must
/// not shift between appearances. Anything used as TEXT directly on `page`/
/// `surface` gets its own adaptive `…Text` companion (the bd#89 pattern),
/// because a single static value cannot hit 4.5:1 in both appearances.
public enum BrewDeskPalette {
    // MARK: - Ramps (design record — see PR contrast table for the math)

    /// Primary/green. Base `#2D5A4C` (ticket-specified) sits at step 5.
    static let primaryRamp = [
        "#0A1411", "#11221D", "#183029", "#1F3E34", "#264C40",
        "#2D5A4C", "#609F8B", "#B0C7C0", "#F7F8F8",
    ]
    /// Secondary/sand. Base `#E8E2D2` (ticket-specified) sits at step 7.
    static let secondaryRamp = [
        "#14120A", "#3B331E", "#625532", "#897746", "#AC975D",
        "#C0B084", "#D4C9AB", "#E8E2D2", "#F8F8F7",
    ]
    /// Tertiary/sage. Base `#769382` (ticket-specified) sits at step 5.
    static let tertiaryRamp = [
        "#0D110F", "#222B26", "#37463D", "#4B6054", "#607A6B",
        "#769382", "#A2B4A9", "#CDD5D0", "#F7F8F7",
    ]
    /// Neutral. Base `#FAF9F6` (ticket-specified) sits at step 8.
    static let neutralRamp = [
        "#14110B", "#393320", "#5E5434", "#847549", "#A79560",
        "#BCAE86", "#D0C7AB", "#E5E0D1", "#FAF9F6",
    ]
    /// Destructive. Base sampled from the reference board's trash-icon fill
    /// (`#983B25` — ticket's `~#B5451B` was an eyeballed approximation; this
    /// is the actual pixel value) sits at step 5.
    static let destructiveRamp = [
        "#150C0A", "#2C1713", "#44221A", "#5F2B1F", "#7A3423",
        "#983B25", "#C17462", "#D3BBB5", "#F8F7F7",
    ]

    // MARK: - Brand hues (static — used as fills/pins behind fixed white
    // text, or as icon glyphs; must NOT change with appearance or every
    // badge/pin/button fill would need its paired text color to change too)

    /// Ink. Inverted-button fill, hairline strokes, dark-on-light chip text.
    public static let espresso = Color(red: 0.169, green: 0.169, blue: 0.169)
    /// Primary green — CTAs, selected chips/pins, tab accent (fill role).
    public static let roast = hex(primaryRamp[5])
    /// Secondary sand — secondary-button fill, chip fill.
    public static let oat = hex(secondaryRamp[7])
    /// Neutral near-white.
    public static let foam = hex(neutralRamp[8])
    /// Tertiary sage — "good" tier fill, icon glyphs, subtle tints.
    public static let moss = hex(tertiaryRamp[5])
    /// Destructive — "weak" tier fill (bd#211; previously unused by any
    /// tier despite its doc history, and previously misdescribed here —
    /// `berry` below was the actual pre-bd#211 "weak" fill) and general
    /// error fill/icon glyphs.
    public static let clay = hex(destructiveRamp[5])
    /// Destructive, deeper. No longer a tier fill as of bd#211 (see `clay`
    /// above) — still used for other destructive states (e.g. "closed"
    /// status) elsewhere in the app.
    public static let berry = hex(destructiveRamp[4])
    /// Sand, deepened for legibility under white text — "mixed" tier fill.
    /// Replaces the old teal `ocean` (unused after the tier re-map onto
    /// green→sage→sand→destructive).
    public static let sand = hex(secondaryRamp[2])
    /// Neutral grey fill for a venue with no Work Fit evidence (bd#159):
    /// deliberately outside the great/good/mixed/weak tier ramp and never
    /// red or green, so "not checked yet" can never be misread as a score
    /// (founder is red-green colorblind). Static, like the tier fills — it
    /// sits behind fixed white badge/pin text in both appearances.
    public static let unobserved = Color(red: 0.58, green: 0.58, blue: 0.60)
    /// Hairline stroke for an unobserved map dot (bd#209) — a darker shade
    /// of `unobserved`, never white. At street-level density dozens of
    /// unobserved dots used to stack into a single white-filled,
    /// white-stroked "worm": a white fill next to a white stroke gave every
    /// overlapping dot the SAME edge color as its neighbour's fill, so the
    /// pile read as one blob with no visible boundaries. A neutral grey fill
    /// with a darker grey edge keeps each dot legible as its own shape even
    /// when several sit close together, without introducing red/green.
    ///
    /// Adaptive (supervisor check at live density, 2026-09-20): the fixed dark
    /// grey vanished against the dark basemap, so unrated cafés were invisible
    /// in dark mode. Dark grey on the light map, light grey on the dark map.
    public static let unobservedDotStroke = adaptive(
        light: Color(red: 0.38, green: 0.38, blue: 0.40),
        dark: Color(red: 0.80, green: 0.81, blue: 0.83)
    )

    // MARK: - bd#211: observed dot fills — single hue, lightness-only tier

    /// Observed map dots used to tint by `ScoreTier.color` directly — four
    /// DIFFERENT hues (green/sage/olive/brick), exactly the kind of signal a
    /// red-green colorblind viewer can't reliably read, and dots carry no
    /// number to fall back on (unlike a pin). These three tokens replace
    /// that: ONE hue (the brand primary green, ~161°) at three lightness
    /// steps — darkest/most saturated = best tier, lightest = weakest.
    /// Capped at 3 steps though there are 4 tiers: `mixed` and `weak` share
    /// the lightest step (`observedDotWeak`) — dots are the high-density,
    /// lower-priority representation; a venue where great-vs-good-vs-mixed-
    /// vs-weak actually matters always wins a PIN slot instead (bd#204/
    /// #209), where the real number carries that distinction.
    ///
    /// Adaptive per appearance rather than one fixed ramp: a single color
    /// can't hit 3:1 against both a light AND a dark basemap at once (the
    /// luminance a light background needs is structurally different from
    /// what a dark one needs), so light mode uses darker steps and dark
    /// mode uses lighter ones, each internally ordered the same way.
    /// Verified (see the bd#211 PR's contrast table): every step is
    /// >=3:1 against `page` in its own appearance, and every adjacent pair
    /// within an appearance is >=1.6:1 apart. Hue spread across all three
    /// steps, either appearance, is under 2° — see `ScoreBadgeContrastTests
    /// .observedDotPaletteIsSingleHueAndLightnessOrdered`.
    static let observedDotGreat = adaptive(light: hex("#0E201A"), dark: hex("#367863"))
    static let observedDotGood = adaptive(light: hex("#20483B"), dark: hex("#48A084"))
    static let observedDotWeak = adaptive(light: hex("#306B59"), dark: hex("#86C8B3"))

    /// `ScoreTier` → the 3-step dot ramp above.
    public static func observedDotColor(for tier: ScoreTier) -> Color {
        switch tier {
        case .great: observedDotGreat
        case .good: observedDotGood
        case .mixed, .weak: observedDotWeak
        }
    }

    /// Hairline stroke for an OBSERVED dot — flips which way it's lighter
    /// than the fill, by appearance, so it always reads as a defined edge:
    /// light mode's fills are very dark (see above), so a light stroke
    /// separates the dot from a light basemap the same way the old
    /// always-white stroke did; dark mode's fills are lighter (so they
    /// already read against a dark basemap on their own), and a dark
    /// stroke instead defines the edge crisply rather than washing out
    /// against an already-light fill.
    public static let observedDotStroke = adaptive(light: foam, dark: hex("#0A1411"))
    /// Muted secondary-text tone (light mode only; dark mode is
    /// `secondaryText` below — "sand becomes text-secondary" in dark).
    /// Between ramp steps 2 and 3: step 3 alone (`#897746`) undershoots
    /// 4.5:1 on `page`/`surface` light (4.16:1 / 4.38:1 — verified), so this
    /// sits a touch darker than the ramp step while staying distinct from
    /// `sand`'s tier-warning fill.
    static let muted = hex("#6B5A44")

    /// Cluster "stack" marker fill (bd#204) — deliberately NEUTRAL, outside
    /// every ScoreTier/brand hue: a cluster count is metadata about density,
    /// never a score, and this must never be mistaken for one at a glance
    /// (the West Village screenshot bug this fixes was exactly that
    /// confusion). Light-mode value reads as elevated chrome on the map's
    /// light base style; dark-mode value is a lifted neutral grey (not
    /// green-tinted `surface`) so it reads as UI chrome rather than another
    /// data pin. Static per-appearance like the tier fills, since it sits
    /// behind its own adaptive text token rather than fixed white.
    public static let clusterSurface = adaptive(
        light: Color(red: 0.97, green: 0.97, blue: 0.96),
        dark: Color(red: 0.26, green: 0.26, blue: 0.28)
    )

    /// Text/glyph color on `clusterSurface` — verified 4.5:1+ in both
    /// appearances (near-black on the light fill, near-white on the dark
    /// fill).
    public static let clusterSurfaceText = adaptive(
        light: espresso,
        dark: foam
    )

    /// Hairline ring around a cluster marker — a touch stronger than the
    /// fill so the "stack" silhouette reads as a distinct object against the
    /// map, without a shadow (perf: no materials/shadows on map annotations,
    /// see the file-level note above).
    public static let clusterSurfaceStroke = adaptive(
        light: Color(red: 0.82, green: 0.82, blue: 0.80),
        dark: Color(red: 0.40, green: 0.40, blue: 0.42)
    )

    // MARK: - bd#212: micro teardrop marker palette — single hue,
    // lightness-only, ramp DIRECTION flips by appearance

    /// Fill for a RATED marker (teardrop or its demoted dot), by score
    /// tier index (0 = `<60`, 1 = `60-69`, 2 = `70-79`, 3 = `>=80`) —
    /// replaces `observedDotGreat/Good/Weak` and every `ScoreTier.color`
    /// use on the map outright (bd#212 deletes the cluster/stack design
    /// these coexisted with).
    ///
    /// DARK basemap: best score is the BRIGHTEST fill (index 3 lightest).
    /// LIGHT basemap: the ramp REVERSES — best score is the DARKEST/most
    /// saturated fill (index 3 darkest) — a light map showing a bright pin
    /// for a bad score would itself be a second, contradictory "lightness"
    /// signal. Either way lightness alone (never hue) carries the tier, so
    /// it reads correctly for a red-green colorblind viewer (`markerTierIsSingleHueAndMonotonic`
    /// in `MarkerPaletteTests` verifies this numerically against the
    /// resolved colors, not just these comments).
    ///
    /// bd#217 (TestFlight build 26 feedback — "change the color of the
    /// text to white on the pins"): the light-map ramp used to carry a DARK
    /// number on its two lighter steps and a light number only on its two
    /// darkest, so most pins in a normal light-mode session ("52", "69",
    /// "45"…) rendered dark-green-on-sage at low contrast. The number is
    /// now WHITE on every light-map tier (`markerNumberLightMap` below), so
    /// the FILL ramp had to darken across the board to hold >=4.5:1 white-
    /// on-fill everywhere, and collapsed to the spec's "at most three
    /// lightness steps" in the process — tiers 0 and 1 (`<60`, `60-69`)
    /// now share the lightest of the three (still darkest-wins ordering,
    /// just not strictly distinct per tier; see
    /// `MarkerPaletteTests.lightMapMarkerFillIsDarkestForTheBestScore`).
    /// Verified contrast (relative luminance, WCAG formula): `#3D8069` vs
    /// white ≈4.68:1, `#2C6B58` ≈6.27:1, `#1C5243` ≈9.0:1 — all comfortably
    /// clear 4.5:1.
    private static let markerFillDarkMap: [Color] = [
        hex("#3A6E5D"), hex("#4F9D82"), hex("#74CDA9"), hex("#A8F0CF"),
    ]
    private static let markerFillLightMap: [Color] = [
        hex("#3D8069"), hex("#3D8069"), hex("#2C6B58"), hex("#1C5243"),
    ]
    /// Number color per tier index, resolved separately for each map
    /// appearance so every step clears >=4.5:1 against its own fill —
    /// verified in `MarkerPaletteTests.markerNumberColorClearsContrastAgainstItsFill`.
    /// Dark map: darkest fill (index 0) needs a light number; the three
    /// brighter fills need a dark one — UNCHANGED by bd#217 (Bilal approved
    /// the dark-mock mint-fill/dark-number pairing as shipped).
    /// Light map: bd#217 makes every tier WHITE — see `markerFillLightMap`'s
    /// doc comment for why (the old split, dark number on the two lighter
    /// tiers, light number on the two darker ones, is exactly what read as
    /// low-contrast dark-green-on-sage in Bilal's TestFlight build 26
    /// screenshot).
    private static let markerNumberDarkMap: [Color] = [
        hex("#E6F2EC"), hex("#08140F"), hex("#08140F"), hex("#08140F"),
    ]
    private static let markerNumberLightMap: [Color] = Array(repeating: hex("#FFFFFF"), count: 4)

    /// Score → tier index (0..3): `<60`, `60-69`, `70-79`, `>=80` — bd#212's
    /// own thresholds, deliberately different from `ScoreTier`'s
    /// (75/60/45): this ramp exists only to place a marker in one of four
    /// LIGHTNESS steps, not to classify "great/good/mixed/weak" for copy.
    static func markerTierIndex(score: Int) -> Int {
        switch score {
        case 80...: 3
        case 70..<80: 2
        case 60..<70: 1
        default: 0
        }
    }

    /// Fill for a rated teardrop/dot marker, adaptive per map appearance.
    public static func markerFill(score: Int) -> Color {
        let index = markerTierIndex(score: score)
        return adaptive(light: markerFillLightMap[index], dark: markerFillDarkMap[index])
    }

    /// Number color for a rated marker's score label, adaptive per map
    /// appearance — always paired with `markerFill(score:)` for the SAME
    /// score, never mixed with a different tier's fill.
    public static func markerNumberColor(score: Int) -> Color {
        let index = markerTierIndex(score: score)
        return adaptive(light: markerNumberLightMap[index], dark: markerNumberDarkMap[index])
    }

    /// Hairline edge on a rated teardrop (bd#212 spec: 0.75pt dark, "no
    /// white ring, ever" — that rule stood for BOTH appearances at the
    /// time).
    ///
    /// bd#217 (Bilal, same PR as the white-number change): "the border...
    /// should be white instead of dark — on the pins," for the LIGHT map
    /// only — he kept the dark mock's dark-hairline-plus-shadow pairing as
    /// shipped for DARK. Adaptive so each appearance can keep its own
    /// answer: light gets a near-opaque white edge (paired with a THINNER
    /// 1pt stroke — see `TeardropMarkerView.hairlineWidth` — so the extra
    /// contrast doesn't read as a bigger pin), dark keeps the exact
    /// bd#212 value unchanged. One value flip here (plus the paired width
    /// in `TeardropMarkerView`) is what "adaptive token" bought: if Bilal
    /// ever wants a white ring on the dark map too, only the `dark:` case
    /// below changes.
    public static let markerHairline = adaptive(
        light: Color.white.opacity(0.95),
        dark: Color(red: 6.0 / 255, green: 18.0 / 255, blue: 14.0 / 255).opacity(0.9)
    )

    /// Faint neutral fill for an unrated (unobserved) venue's speck — never
    /// tier-colored, never red/green (bd#159's "not checked yet" rule
    /// carried into bd#212), and adaptive so it stays visible against both
    /// basemaps rather than the old fixed-dark-grey regression
    /// (`unobservedDotStroke`'s own doc comment documents that exact bug).
    public static let markerSpeckFill = adaptive(
        light: Color(red: 0.42, green: 0.42, blue: 0.44).opacity(0.55),
        dark: Color(red: 0.74, green: 0.76, blue: 0.78).opacity(0.55)
    )

    /// Halo label background behind the selected marker's café name — a
    /// small pill sitting above the 30pt selected head.
    public static let markerHaloBackground = adaptive(
        light: Color(red: 1, green: 1, blue: 1).opacity(0.92),
        dark: Color(red: 0.09, green: 0.13, blue: 0.11).opacity(0.92)
    )
    public static let markerHaloText = adaptive(light: espresso, dark: foam)

    public static let pageGradient = LinearGradient(
        colors: [oat, foam],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Semantic surfaces (brewdesk#62, re-tuned for #98)

    /// Screen background: warm neutral in light mode, deep green-black in
    /// dark. Matches `BrewDeskTheme.backgroundColor` so screens styled
    /// either way read as one app.
    public static let page = adaptive(
        light: hex(neutralRamp[8]),
        dark: hex("#15201C")
    )

    /// Card/section background sitting on `page`.
    public static let surface = adaptive(
        light: Color(red: 1, green: 1, blue: 1),
        dark: hex("#1E2A25")
    )

    /// Inset/nested background sitting on `surface` (chips, wells).
    public static let surfaceSecondary = adaptive(
        light: oat,
        dark: hex("#26332D")
    )

    /// First-launch hero background (onboarding, location primer).
    public static let adaptivePageGradient = LinearGradient(
        colors: [page, surface],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Adaptive text tokens (brewdesk#89, extended for #98)

    /// `clay` used as TEXT (not fill) needs a lighter dark-mode value to
    /// clear 4.5:1 on `surface`/`page` dark. Use for any destructive-family
    /// TEXT; keep `clay` itself for fills/pins.
    public static let clayText = adaptive(
        light: clay,
        dark: hex("#E8967D")
    )

    /// `berry` used as TEXT — same shape as `clayText`.
    public static let berryText = adaptive(
        light: berry,
        dark: hex("#E3A28F")
    )

    /// `moss` used as TEXT fails 4.5:1 on light `page`/`surface` (3.2–3.4:1
    /// at the fill value) — darkened for light, lifted for dark. Use for any
    /// sage-family TEXT (provenance "human source" label, success states);
    /// keep `moss` itself for fills/icons.
    public static let mossText = adaptive(
        light: hex(tertiaryRamp[4]),
        dark: hex(tertiaryRamp[6])
    )

    /// Primary green as TEXT/tint directly on `page`/`surface` — `roast`
    /// itself stays a fixed dark green because it also fills badges/pins
    /// behind fixed white text, but a fixed dark green reads at only 2.1:1
    /// on dark `page`. Lifted to the ticket's "primary-on-dark lifted sage"
    /// value for dark.
    ///
    /// NOT used by `BrewDeskTheme.primaryColor` — that needs a value safe to
    /// ANIMATE (the onboarding page-dot indicator interpolates its opacity),
    /// and this adaptive token crashed there: iOS 26's async render path can
    /// invoke a dynamic `UIColor` provider off the main thread, which trips
    /// a Swift 6 isolation check (`dispatch_assert_queue_fail`). Safe for
    /// static (non-animated) text/tint use; `BrewDeskTheme` resolves the
    /// same two hexes as concrete per-mode `Color`s instead.
    public static let primaryText = adaptive(
        light: roast,
        dark: hex("#8FB3A5")
    )

    /// Secondary/body text — "sand becomes text-secondary" in dark mode.
    /// Same animation caveat as `primaryText` above; not used by
    /// `BrewDeskTheme.secondaryColor`.
    public static let secondaryText = adaptive(
        light: muted,
        dark: hex("#D8CCA9")
    )

    /// The package ships no asset catalog, so adaptive brand colors are built
    /// from a dynamic provider — one definition, both appearances.
    ///
    /// The `Color` → `UIColor` bridge is done ONCE here, not inside the
    /// trait-resolution closure. SwiftUI's async render path (iOS 26) can
    /// invoke a dynamic `UIColor` provider's closure from a background
    /// render thread — doing the Color→UIColor conversion there crashed
    /// (`dispatch_assert_queue_fail` inside `UIDynamicProviderColor
    /// _resolvedColorWithTraitCollection:`, reproduced by animating
    /// `BrewDeskTheme.primaryColor`'s opacity on the onboarding page-dot
    /// indicator once it became adaptive). Pre-resolving both UIColors here
    /// means the closure itself only ever picks between two already-built
    /// values — no conversion work happens on the resolution thread.
    private static func adaptive(light: Color, dark: Color) -> Color {
        let lightColor = UIColor(light)
        let darkColor = UIColor(dark)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
    }

    private static func hex(_ value: String) -> Color {
        var s = value
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        return Color(
            red: Double((rgb & 0xFF0000) >> 16) / 255,
            green: Double((rgb & 0x00FF00) >> 8) / 255,
            blue: Double(rgb & 0x0000FF) / 255
        )
    }
}

public extension View {
    @ViewBuilder
    func brewDeskGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}
