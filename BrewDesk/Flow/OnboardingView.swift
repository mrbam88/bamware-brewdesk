import BrewDeskKit
import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    let configuration: AppConfiguration
    let onComplete: () -> Void
    @State private var page = 0

    // First launch was cream in every appearance (ui-review-2026-08-22):
    // `AppBrand.pageGradient`/`.espresso`/`.muted` never adapted, so
    // onboarding stayed light-only under system dark mode. `theme` mirrors
    // the adaptive colors every other screen already uses.
    private var theme: BrewDeskTheme { BrewDeskTheme(isDarkMode: colorScheme == .dark) }

    // AppBrand.clay measures well under 4.5:1 on the new dark page background
    // (audit-caught: testOnboardingAccessibilityAudit, "Contrast failed" on
    // the eyebrow label) -- brighten it for dark instead of reusing the
    // fixed light-mode value.
    private var eyebrowColor: Color {
        colorScheme == .dark ? Color(red: 0.98, green: 0.62, blue: 0.46) : AppBrand.clay
    }

    // theme.secondaryColor's dark value (0.62/0.56/0.50) also measured under
    // 4.5:1 on this page's darkest gradient corner (same audit-caught issue,
    // body copy this time) -- a brighter body-text color for this screen only.
    private var bodyTextColor: Color {
        colorScheme == .dark ? Color(red: 0.82, green: 0.77, blue: 0.71) : theme.secondaryColor
    }

    private let pages = [
        OnboardingPage(
            eyebrow: "WORK, WITHOUT THE GUESSWORK",
            title: "Your next desk might serve espresso.",
            body: "Find nearby cafes where the Wi-Fi works, outlets exist, and opening a laptop is actually welcome.",
            symbol: "cup.and.saucer.fill"
        ),
        OnboardingPage(
            eyebrow: "THE SIGNALS THAT MATTER",
            title: "Know before you order.",
            body: "Compare noise, Wi-Fi, outlets, and laptop policy instead of digging through hundreds of reviews.",
            symbol: "waveform.path.ecg.rectangle.fill"
        ),
        OnboardingPage(
            eyebrow: "HONEST BY DESIGN",
            title: "Every score shows its work.",
            body: "Measured facts lead. Estimates stay labeled. Sources and verification dates show how much to trust.",
            symbol: "checkmark.seal.fill"
        ),
    ]

    var body: some View {
        ZStack {
            AppBrand.adaptivePageGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(configuration.appName.uppercased())
                        .font(.caption.bold())
                        .tracking(2.4)
                    Spacer()
                    Text("0\(page + 1) / 03")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(bodyTextColor)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        onboardingPage(item)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? theme.primaryColor : theme.primaryColor.opacity(0.15))
                            .frame(width: index == page ? 30 : 8, height: 8)
                    }
                }
                .animation(reduceMotion ? nil : .snappy, value: page)
                .accessibilityHidden(true)

                Button(page == pages.count - 1 ? "Find my work cafe" : "Continue") {
                    if page == pages.count - 1 {
                        onComplete()
                    } else {
                        if reduceMotion {
                            page += 1
                        } else {
                            withAnimation { page += 1 }
                        }
                    }
                }
                .buttonStyle(PrimaryActionStyle())
                .padding(24)
            }
        }
    }

    private func onboardingPage(_ item: OnboardingPage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 16 : 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 42)
                        .fill(AppBrand.roast)
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? 150 : 230)
                        .rotationEffect(.degrees(reduceMotion ? 0 : -3))
                    Image(systemName: item.symbol)
                        .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 62 : 92, weight: .light))
                        .foregroundStyle(AppBrand.oat)
                        .accessibilityHidden(true)
                }
                Text(item.eyebrow)
                    .font(.footnote.weight(.black))
                    .foregroundStyle(eyebrowColor)
                    .lineLimit(nil)
                Text(item.title)
                    .font(.largeTitle.bold())
                    .fontDesign(.serif)
                    .foregroundStyle(theme.primaryColor)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.body)
                    .font(.body)
                    .foregroundStyle(bodyTextColor)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 24)
        }
        .padding(.horizontal, 24)
    }
}

private struct OnboardingPage {
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    let body: LocalizedStringKey
    let symbol: String
}
