import StoreKit
import SwiftUI

struct PaywallView: View {
    let configuration: AppConfiguration
    @Bindable var store: SubscriptionStore

    var body: some View {
        ZStack {
            AppBrand.espresso.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(AppBrand.clay)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("MAKE EVERY\nCOFFEE RUN COUNT.")
                            .font(.system(size: 46, weight: .black, design: .rounded))
                            .foregroundStyle(AppBrand.foam)
                            .minimumScaleFactor(0.8)
                        Text("Unlimited work-cafe discovery, precise filters, and live Work Fit signals.")
                            .font(.title3)
                            .foregroundStyle(AppBrand.oat.opacity(0.76))
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        benefit("wifi", "Filter for Wi-Fi you can rely on")
                        benefit("powerplug.fill", "Find outlets before your battery hits 5%")
                        benefit("laptopcomputer", "Avoid places where laptops are discouraged")
                    }

                    if store.isLoading {
                        ProgressView("Loading plans…")
                            .tint(AppBrand.oat)
                            .foregroundStyle(AppBrand.oat)
                            .frame(maxWidth: .infinity)
                    } else if store.products.isEmpty {
                        unavailablePlans
                    } else {
                        ForEach(store.products, id: \.id) { product in
                            planButton(product)
                        }
                    }

                    if let error = store.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.red.opacity(0.9))
                            .frame(maxWidth: .infinity)
                    }

                    Button("Restore purchases") { Task { await store.restore() } }
                        .font(.subheadline.bold())
                        .foregroundStyle(AppBrand.oat)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 18) {
                        Link("Terms", destination: configuration.termsURL)
                        Link("Privacy", destination: configuration.privacyURL)
                    }
                    .font(.caption)
                    .foregroundStyle(AppBrand.oat.opacity(0.65))
                    .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
        }
    }

    private func benefit(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppBrand.oat)
    }

    private func planButton(_ product: Product) -> some View {
        Button {
            Task { await store.purchase(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.headline)
                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(AppBrand.muted)
                        .lineLimit(2)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.title3.bold())
            }
            .foregroundStyle(AppBrand.espresso)
            .padding(18)
            .background(AppBrand.foam, in: RoundedRectangle(cornerRadius: 22))
        }
        .disabled(store.isPurchasing)
    }

    private var unavailablePlans: some View {
        VStack(spacing: 12) {
            Text("StoreKit plans are not loaded yet.")
                .foregroundStyle(AppBrand.oat)
            #if DEBUG
            Button { store.grantDevelopmentAccess() } label: {
                Text("Continue in development")
                    .font(.headline)
                    .foregroundStyle(AppBrand.espresso)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(AppBrand.oat, in: Capsule())
            }
            #endif
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
