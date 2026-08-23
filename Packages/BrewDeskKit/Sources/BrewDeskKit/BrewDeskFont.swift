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
        custom("HankenGrotesk-Regular", fallbackDesign: .default, weight: weight, style: style)
    }

    /// Body face: Manrope.
    public static func body(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        custom("Manrope-Regular", fallbackDesign: .default, weight: weight, style: style)
    }

    /// Label/eyebrow/numeric face: JetBrains Mono — e.g. the "WORK FIT"
    /// eyebrow and score digits.
    public static func label(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        custom("JetBrainsMono-Regular", fallbackDesign: .monospaced, weight: weight, style: style)
    }

    /// Whether each bundled family actually registered — read by
    /// `BrewDeskFontTests` so a bundling regression fails a test instead of
    /// silently falling back app-wide.
    public static var hankenGroteskLoaded: Bool { resolves("HankenGrotesk-Regular") }
    public static var manropeLoaded: Bool { resolves("Manrope-Regular") }
    public static var jetBrainsMonoLoaded: Bool { resolves("JetBrainsMono-Regular") }

    private static func resolves(_ postScriptName: String) -> Bool {
        UIFont(name: postScriptName, size: 12) != nil
    }

    private static func custom(
        _ name: String,
        fallbackDesign: Font.Design,
        weight: Font.Weight,
        style: Font.TextStyle
    ) -> Font {
        guard resolves(name) else {
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
