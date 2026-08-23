import BrewDeskKit
import SwiftUI

struct LocationPermissionView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    let locationService: LocationService
    let onComplete: () -> Void

    // Same fix as OnboardingView (ui-review-2026-08-22): this screen painted
    // the light-only cream gradient regardless of system appearance.
    private var theme: BrewDeskTheme { BrewDeskTheme(isDarkMode: colorScheme == .dark) }

    var body: some View {
        ZStack {
            AppBrand.adaptivePageGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 18 : 28) {
                    ZStack {
                        Circle()
                            .fill(AppBrand.moss.opacity(0.14))
                            .frame(
                                width: dynamicTypeSize.isAccessibilitySize ? 160 : 230,
                                height: dynamicTypeSize.isAccessibilitySize ? 160 : 230
                            )
                        Image(systemName: "location.fill.viewfinder")
                            .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 64 : 92, weight: .light))
                            .foregroundStyle(AppBrand.moss)
                            .accessibilityHidden(true)
                    }
                    VStack(spacing: 12) {
                        Text("Start where you are.")
                            .font(.largeTitle.bold())
                            .fontDesign(.serif)
                            .foregroundStyle(theme.primaryColor)
                        Text("Your location finds spots nearby. It is never included in a public report.")
                            .font(.title3)
                            .foregroundStyle(theme.secondaryColor)
                            .multilineTextAlignment(.center)
                    }
                    Button("Use my location") {
                        locationService.requestAccess()
                        onComplete()
                    }
                    .buttonStyle(PrimaryActionStyle())
                    Button("Use Union Square instead") { onComplete() }
                        .font(.subheadline.bold())
                        .foregroundStyle(theme.secondaryColor)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(24)
            }
        }
    }
}
