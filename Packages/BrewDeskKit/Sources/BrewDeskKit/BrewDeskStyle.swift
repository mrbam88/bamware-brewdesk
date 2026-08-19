import SwiftUI

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
