// Community capture prototype — flow container, guide + submitted states
// (brewdesk#46). This entire file compiles ONLY into Debug builds — the App
// Store binary contains none of it (Guideline 2.3.1).
// Spec: docs/community-capture-ux.md.
#if DEBUG
import SwiftUI
import VenueKit

/// The guided contribution flow, presented as a sheet from the venue detail
/// toolbar. Owns the model; each stage renders its own screen.
public struct CaptureFlowScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var model: CaptureFlowModel
    @State private var showDiscardAlert = false
    private let venueName: String

    public init(venue: Venue, service: any CaptureSubmissionService) {
        venueName = venue.name
        _model = State(initialValue: CaptureFlowModel(venueID: venue.id, service: service))
    }

    private var theme: BrewDeskTheme { BrewDeskTheme(isDarkMode: colorScheme == .dark) }

    public var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundColor.ignoresSafeArea()
                content
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.stage != .submitted {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { cancelTapped() }
                            .disabled(model.isSubmitting)
                            .accessibilityIdentifier("capture-cancel")
                    }
                }
            }
            .alert("Discard your photos?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("Your ^[\(model.photoCount) photo](inflect: true) won't be saved.")
            }
        }
        // Swipe-down must not silently eat photos; Cancel owns the discard
        // conversation. Before any photo exists there is nothing to lose.
        .interactiveDismissDisabled(model.hasAnyPhoto && model.stage != .submitted)
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .guide:
            CaptureGuideView(venueName: venueName, steps: model.steps, theme: theme) {
                model.start()
            }
        case .shoot(let stepIndex):
            CaptureShootStepView(model: model, stepIndex: stepIndex, theme: theme)
        case .confirm:
            CaptureConfirmView(model: model, theme: theme)
        case .submitted:
            CaptureSubmittedView(venueName: venueName, theme: theme) { dismiss() }
        }
    }

    private func cancelTapped() {
        if model.hasAnyPhoto {
            showDiscardAlert = true
        } else {
            dismiss()
        }
    }
}

/// Supporting copy in the capture flow. `.secondary` fails the accessibility
/// contrast audit on the oat background, and *any* translucent text (e.g.
/// `.primary` + `.opacity`) keeps failing because the audit mis-estimates
/// alpha-composited glyphs — both verified on the iPhone 17e audit runs for
/// brewdesk#46. So supporting text is a fully opaque dynamic gray with
/// comfortable contrast on the theme backgrounds in both modes.
extension View {
    func captureSupportingText() -> some View {
        foregroundStyle(
            Color(
                uiColor: UIColor { traits in
                    traits.userInterfaceStyle == .dark
                        ? UIColor(white: 0.75, alpha: 1)
                        : UIColor(white: 0.25, alpha: 1)
                }
            )
        )
    }
}

/// Guide — "Help map this cafe": sets expectations in under 10 seconds and
/// primes the three-shot sequence. The only place the whole list appears.
struct CaptureGuideView: View {
    let venueName: String
    let steps: [CaptureShotKind]
    let theme: BrewDeskTheme
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Help map \(venueName)")
                        .font(.title.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Three quick photos help remote workers know what to expect. Takes about a minute.")
                        .font(.body)
                        .captureSupportingText()
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 14) {
                    ForEach(steps) { step in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: step.systemImage)
                                .font(.title3)
                                .foregroundStyle(theme.primaryColor)
                                .frame(width: 32)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.title)
                                    .font(.headline)
                                Text(step.why)
                                    .font(.subheadline)
                                    .captureSupportingText()
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(18)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                Label("Try not to include people's faces.", systemImage: "person.crop.circle.badge.xmark")
                    .font(.footnote)
                    .captureSupportingText()
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                onStart()
            } label: {
                Text("Start — 3 photos")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.primaryColor)
            .accessibilityIdentifier("capture-start")
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .navigationTitle("Add photos")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-guide")
    }
}

/// Submitted — thank you: instant gratitude, one exit, job done.
struct CaptureSubmittedView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let venueName: String
    let theme: BrewDeskTheme
    let onDone: () -> Void
    @State private var celebrated = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(theme.primaryColor)
                .scaleEffect(celebrated || reduceMotion ? 1 : 0.5)
                .animation(reduceMotion ? nil : .spring(duration: 0.4), value: celebrated)
                .accessibilityHidden(true)
            Text("Thank you!")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Your photos for \(venueName) are in review. You just made someone's workday easier.")
                .font(.body)
                .captureSupportingText()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .safeAreaInset(edge: .bottom) {
            Button {
                onDone()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.primaryColor)
            .accessibilityIdentifier("capture-done")
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .onAppear { celebrated = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-submitted")
    }
}
#endif
