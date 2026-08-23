import SwiftUI
import BrewDeskKit

typealias AppBrand = BrewDeskPalette

/// Warm Utilitarian button shape (brewdesk#98): rounded rectangle, not the
/// old full capsule — matches the reference board's radius ≈10 buttons.
private let brewDeskButtonShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

/// Primary: green fill, light text. The main-CTA style.
struct PrimaryActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BrewDeskFont.headline(.headline))
            .foregroundStyle(AppBrand.foam)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppBrand.roast.opacity(configuration.isPressed ? 0.78 : 1), in: brewDeskButtonShape)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Secondary: sand fill, ink text.
struct SecondaryActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BrewDeskFont.headline(.headline))
            .foregroundStyle(AppBrand.espresso)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppBrand.oat.opacity(configuration.isPressed ? 0.78 : 1), in: brewDeskButtonShape)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Inverted: ink fill, light text — the pre-#98 `PrimaryActionStyle` look,
/// kept as its own named style for call sites that want the darker chrome.
struct InvertedActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BrewDeskFont.headline(.headline))
            .foregroundStyle(AppBrand.foam)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppBrand.espresso.opacity(configuration.isPressed ? 0.78 : 1), in: brewDeskButtonShape)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Outlined: 1pt ink stroke, ink text, no fill.
struct OutlinedActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BrewDeskFont.headline(.headline))
            .foregroundStyle(AppBrand.espresso.opacity(configuration.isPressed ? 0.6 : 1))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(brewDeskButtonShape.strokeBorder(AppBrand.espresso, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
