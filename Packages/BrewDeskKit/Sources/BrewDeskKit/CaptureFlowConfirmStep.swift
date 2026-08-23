// Community capture prototype — confirm step (brewdesk#46).
// This entire file compiles ONLY into Debug builds — the App Store binary
// contains none of it (Guideline 2.3.1). Spec: docs/community-capture-ux.md.
#if DEBUG
import SwiftUI

/// "Ready to send?" — one look at the three labeled slots, tap any slot to
/// retake, then commit. A skipped slot is visible honesty, no shame copy.
struct CaptureConfirmView: View {
    @Bindable var model: CaptureFlowModel
    let theme: BrewDeskTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Ready to send?")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 12) {
                    ForEach(model.steps) { step in
                        slotRow(for: step)
                    }
                }

                Text("Photos are reviewed before they appear in BrewDesk.")
                    .font(.footnote)
                    .captureSupportingText()

                if model.submissionFailed {
                    Label(
                        model.submissionErrorMessage
                            ?? "Couldn't send your photos. Check your connection and try again.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(BrewDeskPalette.clayText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("capture-error")
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .navigationTitle("Add photos")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-confirm")
    }

    private func slotRow(for step: CaptureShotKind) -> some View {
        Button {
            model.retake(step)
        } label: {
            HStack(spacing: 14) {
                thumbnail(for: step)
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(statusText(for: step))
                        .font(.subheadline)
                        .captureSupportingText()
                }
                Spacer(minLength: 8)
                Text("Retake")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.primaryColor)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isSubmitting)
        .accessibilityLabel("\(step.title), \(statusText(for: step))")
        .accessibilityHint("Retakes this shot")
        .accessibilityIdentifier("capture-slot-\(step.rawValue)")
    }

    @ViewBuilder
    private func thumbnail(for step: CaptureShotKind) -> some View {
        if case .photo(let image) = model.result(for: step) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
        } else {
            // A glyph, not text: a caption in this fixed-size thumbnail
            // clips at accessibility Dynamic Type sizes (audit finding).
            // The row's scaling status text carries the word "Skipped".
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .systemFill))
                Image(systemName: "camera.slash")
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .frame(width: 84, height: 56)
            .accessibilityHidden(true)
        }
    }

    private func statusText(for step: CaptureShotKind) -> String {
        if case .photo = model.result(for: step) {
            "Photo added"
        } else {
            "Skipped"
        }
    }

    private var footer: some View {
        Button {
            Task { await model.submit() }
        } label: {
            HStack(spacing: 8) {
                if model.isSubmitting {
                    ProgressView()
                        .tint(.white)
                }
                Text(submitTitle)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.primaryColor)
        .disabled(model.isSubmitting)
        .accessibilityIdentifier("capture-submit")
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        // Solid theme background, not .bar: the audit's contrast check
        // cannot resolve text over blur materials and fails regardless of
        // the actual ratio (bd#46 audit run — roast on near-white flagged).
        .background(theme.backgroundColor)
    }

    private var submitTitle: String {
        if model.isSubmitting {
            "Sending…"
        } else if model.submissionFailed {
            "Try again"
        } else {
            "Submit photos"
        }
    }
}
#endif
