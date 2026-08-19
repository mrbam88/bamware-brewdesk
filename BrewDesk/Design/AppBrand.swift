import SwiftUI
import BrewDeskKit

typealias AppBrand = BrewDeskPalette

struct PrimaryActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppBrand.foam)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppBrand.espresso.opacity(configuration.isPressed ? 0.78 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
