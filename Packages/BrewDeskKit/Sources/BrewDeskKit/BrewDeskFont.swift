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
    /// bd#241 (Bilal's round-3 pin selection, `weight: 600`): SEMIBOLD at
    /// every head size now, replacing bd#221's flat REGULAR (400) — the
    /// bundled `HankenGrotesk[wght].ttf` is a variable font whose `wght`
    /// axis spans 100–900 with a real named "SemiBold" instance at 600
    /// (verified against the font's own `fvar` table), so `.weight(.semibold)`
    /// asks for a weight the face actually has rather than synthesizing one
    /// it doesn't — unlike the DIFFERENT bug `markerLabel` hit below
    /// (`.custom(_:fixedSize:).weight(...)` malforming a weight the static
    /// "-Regular" instance had to fake).
    public static func markerNumber(size: CGFloat) -> Font {
        let base: Font = hankenGroteskLoaded
            ? .custom("HankenGrotesk-Regular", fixedSize: size)
            : .system(size: size, design: .default)
        return base.weight(.semibold).monospacedDigit()
    }

    /// bd#221 "names on": the café-name label drawn beside a top pin's
    /// head — fixed 11pt Semibold (Apple POI label style), deliberately
    /// NOT Dynamic-Type-scaled for the same reason `markerNumber` isn't:
    /// it has to fit the collision-checked screen-space box the planner
    /// already reserved for it.
    ///
    /// Supervisor review (bd#221 round 2 — "renders far larger than the
    /// reference, ≈15-16pt vs the specified 11pt"): the first cut chained
    /// `.custom("HankenGrotesk-Regular", fixedSize: 11).weight(.semibold)`
    /// — `markerNumber` above uses the identical pattern at a genuinely
    /// fixed size, so the bug wasn't Dynamic Type scaling the FONT; it was
    /// this call asking a custom face registered under the PostScript name
    /// "…-Regular" to synthesize a heavier weight it doesn't have. Unlike
    /// `markerNumber` (always `.weight(.regular)`, the face's own real
    /// weight, no synthesis needed), that produced an oversized/malformed
    /// glyph run instead of a clean bold. `.system(size:weight:)` is a
    /// real multi-weight family — semibold synthesis just works there —
    /// so the label now uses the system face outright at a true fixed
    /// 11pt, per the supervisor's own fix.
    ///
    /// `accessibilityBump`: this still isn't FULLY Dynamic-Type-deaf —
    /// once the reader's text size crosses into an actual accessibility
    /// category (`DynamicTypeSize.isAccessibilitySize`), the label bumps
    /// to a capped 13pt rather than staying frozen at 11pt forever; below
    /// that threshold (every normal, non-accessibility setting) it's
    /// exactly 11pt, matching the spec and the reference.
    public static func markerLabel(accessibilityBump: Bool = false) -> Font {
        .system(size: accessibilityBump ? 13 : 11, weight: .semibold, design: .default)
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
