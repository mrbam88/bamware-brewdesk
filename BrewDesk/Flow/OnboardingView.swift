import SwiftUI

struct OnboardingView: View {
    let configuration: AppConfiguration
    let onComplete: () -> Void
    @State private var page = 0

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
            AppBrand.pageGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(configuration.appName.uppercased())
                        .font(.caption.bold())
                        .tracking(2.4)
                    Spacer()
                    Text("0\(page + 1) / 03")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppBrand.muted)
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
                            .fill(index == page ? AppBrand.espresso : AppBrand.espresso.opacity(0.15))
                            .frame(width: index == page ? 30 : 8, height: 8)
                    }
                }
                .animation(.snappy, value: page)

                Button(page == pages.count - 1 ? "Find my work cafe" : "Continue") {
                    if page == pages.count - 1 {
                        onComplete()
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .buttonStyle(PrimaryActionStyle())
                .padding(24)
            }
        }
    }

    private func onboardingPage(_ item: OnboardingPage) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 42)
                    .fill(AppBrand.roast)
                    .frame(height: 230)
                    .rotationEffect(.degrees(-3))
                Image(systemName: item.symbol)
                    .font(.system(size: 92, weight: .light))
                    .foregroundStyle(AppBrand.oat)
            }
            Text(item.eyebrow)
                .font(.caption.bold())
                .tracking(1.8)
                .foregroundStyle(AppBrand.clay)
            Text(item.title)
                .font(.system(size: 40, weight: .bold, design: .serif))
                .foregroundStyle(AppBrand.espresso)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.body)
                .font(.body)
                .foregroundStyle(AppBrand.muted)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

private struct OnboardingPage {
    let eyebrow: String
    let title: String
    let body: String
    let symbol: String
}
