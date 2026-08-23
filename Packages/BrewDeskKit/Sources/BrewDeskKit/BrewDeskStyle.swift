import SwiftUI
import UIKit

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
    /// Destructive — "mixed" tier / error fill and icon glyphs.
    public static let clay = hex(destructiveRamp[5])
    /// Destructive, deeper — "weak" tier fill.
    public static let berry = hex(destructiveRamp[4])
    /// Sand, deepened for legibility under white text — "mixed" tier fill.
    /// Replaces the old teal `ocean` (unused after the tier re-map onto
    /// green→sage→sand→destructive).
    public static let sand = hex(secondaryRamp[2])
    /// Muted secondary-text tone (light mode only; dark mode is
    /// `secondaryText` below — "sand becomes text-secondary" in dark).
    /// Between ramp steps 2 and 3: step 3 alone (`#897746`) undershoots
    /// 4.5:1 on `page`/`surface` light (4.16:1 / 4.38:1 — verified), so this
    /// sits a touch darker than the ramp step while staying distinct from
    /// `sand`'s tier-warning fill.
    static let muted = hex("#6B5A44")

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
