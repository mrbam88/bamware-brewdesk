import SwiftUI

enum AppBrand {
    static let espresso = Color(red: 0.17, green: 0.11, blue: 0.08)
    static let roast = Color(red: 0.31, green: 0.19, blue: 0.12)
    static let oat = Color(red: 0.97, green: 0.94, blue: 0.88)
    static let foam = Color(red: 1.00, green: 0.98, blue: 0.94)
    static let moss = Color(red: 0.24, green: 0.38, blue: 0.27)
    static let clay = Color(red: 0.73, green: 0.35, blue: 0.20)
    static let muted = Color(red: 0.47, green: 0.42, blue: 0.38)

    static let pageGradient = LinearGradient(
        colors: [oat, foam],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

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
