import SwiftUI

/// "How Work Fit is scored" — transparency page. Every statement here
/// mirrors bamware-venue-engine src/scoring.ts (v2); if the formula changes
/// there, this copy changes in the same breath. No aspirational claims.
public struct MethodologyScreen: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section(
                    "What we measure",
                    icon: "list.clipboard",
                    body: "methodology_what_body"
                )
                section(
                    "How the score is weighted",
                    icon: "scalemass",
                    body: "methodology_weights_body"
                )
                section(
                    "Why every claim shows its source",
                    icon: "checkmark.seal",
                    body: "methodology_provenance_body"
                )
                section(
                    "Fresh beats stale",
                    icon: "clock.arrow.circlepath",
                    body: "methodology_decay_body"
                )
                section(
                    "Honest unknowns",
                    icon: "questionmark.circle",
                    body: "methodology_unknowns_body"
                )
            }
            .padding(20)
        }
        .navigationTitle(Text("How Work Fit works"))
        .navigationBarTitleDisplayMode(.large)
        // Brand page + surface tokens instead of stock grouped grays
        // (ui-review-2026-08-21 finding 3).
        .background(BrewDeskPalette.page.ignoresSafeArea())
    }

    private func section(_ title: LocalizedStringKey, icon: String, body key: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.tint)
            Text(key)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(BrewDeskPalette.surface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
