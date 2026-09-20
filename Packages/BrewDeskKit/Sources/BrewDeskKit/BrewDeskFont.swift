import SwiftUI
import UIKit

/// Type system for Warm Utilitarian (brewdesk#98): headline **Hanken
/// Grotesk**, body **Manrope**, labels/eyebrows/numbers **JetBrains Mono**
/// (all OFL). The three variable TTFs live in `BrewDesk/Fonts/` and are
/// declared in `UIAppFonts` in both `BrewDesk-Debug-Info.plist` and
/// `BrewDesk-Store-Info.plist`.
///
/// Every function wraps `Font.custom(_:size:relativeTo:)`, so Dynamic Type
/// keeps scaling from a real base size instead of a fixed point size. If a
/// family's PostScript name doesn't resolve — bundling regressed, or this
/// runs somewhere the fonts weren't registered (SwiftUI previews, a host app
/// that doesn't declare `UIAppFonts`) — each call falls back to the nearest
/// system design rather than silently drawing with the wrong face.
public enum BrewDeskFont {
    /// Headline face: Hanken Grotesk.
    public static func headline(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        custom("HankenGrotesk-Regular", loaded: hankenGroteskLoaded, fallbackDesign: .default, weight: weight, style: style)
    }

    /// Body face: Manrope.
    public static func body(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        custom("Manrope-Regular", loaded: manropeLoaded, fallbackDesign: .default, weight: weight, style: style)
    }

    /// Label/eyebrow/numeric face: JetBrains Mono — e.g. the "WORK FIT"
    /// eyebrow and score digits.
    public static func label(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        custom("JetBrainsMono-Regular", loaded: jetBrainsMonoLoaded, fallbackDesign: .monospaced, weight: weight, style: style)
    }

    /// Fixed-size (never Dynamic-Type-scaled) Hanken Grotesk for the tiny
    /// score numbers drawn directly on a map marker (bd#212): a marker's
    /// number size is derived from its own pixel diameter (≈0.58× the
    /// head), not from the reader's text-size setting, so this deliberately
    /// skips `Font.custom(_:size:relativeTo:)`'s Dynamic-Type scaling that
    /// every other `BrewDeskFont` case uses — a marker growing past its
    /// collision footprint under Larger Text would itself start overlapping
    /// neighbours. `.monospacedDigit()` gives the tabular figures the spec
    /// calls for (a "1" and a "9" occupy the same width, so a marker's
    /// number never visibly reflows the shape around it).
    ///
    /// bd#217: LIGHT (300) is the bd#212 spec weight and stays the default
    /// for every normal-size teardrop, but at the two smallest head sizes
    /// that still show a number (11.5pt/12.5pt — below `headDiameter <
    /// 15`, ≈6.7pt/7.3pt of actual glyph), white-on-fill Light read too
    /// thin in this PR's own light-map screenshots to be a real legibility
    /// win over the fix it's shipping. Bumped to REGULAR (400, never bold)
    /// only for those small heads — every teardrop at 17pt/20pt/the fixed
    /// 30pt selected size keeps Light.
    public static func markerNumber(size: CGFloat, headDiameter: CGFloat) -> Font {
        let weight: Font.Weight = headDiameter < 15 ? .regular : .light
        let base: Font = hankenGroteskLoaded
            ? .custom("HankenGrotesk-Regular", fixedSize: size)
            : .system(size: size, design: .default)
        return base.weight(weight).monospacedDigit()
    }

    /// Whether each bundled family actually registered — read by
    /// `BrewDeskFontTests` so a bundling regression fails a test instead of
    /// silently falling back app-wide. `UIFont(name:size:)` does real font
    /// matching, so each is resolved once and cached (`static let`) rather
    /// than on every SwiftUI body evaluation — `headline`/`body`/`label`
    /// are called from view bodies, which can re-run many times a second
    /// during a transition/animation.
    public static let hankenGroteskLoaded = resolves("HankenGrotesk-Regular")
    public static let manropeLoaded = resolves("Manrope-Regular")
    public static let jetBrainsMonoLoaded = resolves("JetBrainsMono-Regular")

    private static func resolves(_ postScriptName: String) -> Bool {
        UIFont(name: postScriptName, size: 12) != nil
    }

    private static func custom(
        _ name: String,
        loaded: Bool,
        fallbackDesign: Font.Design,
        weight: Font.Weight,
        style: Font.TextStyle
    ) -> Font {
        guard loaded else {
            return .system(style, design: fallbackDesign).weight(weight)
        }
        return .custom(name, size: baseSize(for: style), relativeTo: style).weight(weight)
    }

    /// Apple's standard base point size per text style at the default
    /// content size category — `Font.custom(_:size:relativeTo:)` needs an
    /// explicit base to scale Dynamic Type from.
    private static func baseSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}
