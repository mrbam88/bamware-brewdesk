import SwiftUI
import UIKit

public enum BrewDeskPalette {
    public static let espresso = Color(red: 0.17, green: 0.11, blue: 0.08)
    public static let roast = Color(red: 0.31, green: 0.19, blue: 0.12)
    public static let oat = Color(red: 0.97, green: 0.94, blue: 0.88)
    public static let foam = Color(red: 1.00, green: 0.98, blue: 0.94)
    public static let moss = Color(red: 0.24, green: 0.38, blue: 0.27)
    public static let clay = Color(red: 0.65, green: 0.26, blue: 0.13)
    public static let ocean = Color(red: 0.00, green: 0.36, blue: 0.42)
    public static let berry = Color(red: 0.50, green: 0.12, blue: 0.15)
    public static let muted = Color(red: 0.40, green: 0.35, blue: 0.31)

    public static let pageGradient = LinearGradient(
        colors: [oat, foam],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Semantic surfaces (brewdesk#62)

    /// Screen background: cream in light mode, deep espresso in dark.
    /// Matches `BrewDeskTheme.backgroundColor` so screens styled either way
    /// read as one app.
    public static let page = adaptive(
        light: oat,
        dark: Color(red: 0.11, green: 0.09, blue: 0.08)
    )

    /// Card/section background sitting on `page` — replaces ad-hoc
    /// `Color(uiColor: .secondarySystemBackground)` usages that fell back to
    /// stock gray (ui-review-2026-08-21 finding 3).
    public static let surface = adaptive(
        light: foam,
        dark: Color(red: 0.16, green: 0.13, blue: 0.11)
    )

    /// Inset/nested background sitting on `surface` (chips, wells).
    public static let surfaceSecondary = adaptive(
        light: Color(red: 0.93, green: 0.89, blue: 0.82),
        dark: Color(red: 0.21, green: 0.17, blue: 0.14)
    )

    /// First-launch hero background (onboarding, location primer): the same
    /// cream gradient as `pageGradient` in light — built from `page` and
    /// `surface`, so it flips to a dark gradient instead of painting cream
    /// straight over a dark system (ui-review-2026-08-22 finding: first
    /// launch was light-only in dark mode).
    public static let adaptivePageGradient = LinearGradient(
        colors: [page, surface],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Adaptive text tokens (brewdesk#89)

    /// `clay` used as TEXT (not fill) fails contrast on `surface` dark —
    /// 2.58:1, well under the 4.5:1 AA floor. Brightened dark value matches
    /// the fix already proven in `OnboardingView.eyebrowColor`
    /// (audit-caught: "Contrast failed" on the eyebrow label). Use this for
    /// any red-family TEXT; keep `clay` itself for fills/pins, which stay as
    /// they are.
    public static let clayText = adaptive(
        light: clay,
        dark: Color(red: 0.98, green: 0.62, blue: 0.46)
    )

    /// `berry` used as TEXT fails contrast on `surface` dark — 1.60:1.
    /// Lightened/desaturated dark value verified at 5.99:1 on `surface`
    /// dark. Use this for any red-family TEXT; keep `berry` itself for
    /// fills/pins, which stay as they are.
    public static let berryText = adaptive(
        light: berry,
        dark: Color(red: 0.92, green: 0.50, blue: 0.55)
    )

    /// The package ships no asset catalog, so adaptive brand colors are built
    /// from a dynamic provider — one definition, both appearances.
    private static func adaptive(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
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
