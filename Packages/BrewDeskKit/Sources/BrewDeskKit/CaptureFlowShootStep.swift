// Community capture prototype — shoot step (brewdesk#46).
// This entire file compiles ONLY into Debug builds — the App Store binary
// contains none of it (Guideline 2.3.1). Spec: docs/community-capture-ux.md.
#if DEBUG
import PhotosUI
import SwiftUI

/// One ask per step: progress header, the ask, the why, a capture area, and
/// Next/Skip. On device the capture area becomes the camera; the prototype
/// offers PhotosPicker plus a deterministic sample-photo button so the flow
/// is fully drivable in the simulator and in UI tests.
struct CaptureShootStepView: View {
    @Bindable var model: CaptureFlowModel
    let stepIndex: Int
    let theme: BrewDeskTheme
    @State private var pickerItem: PhotosPickerItem?

    private var kind: CaptureShotKind { model.steps[stepIndex] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                progressHeader

                VStack(alignment: .leading, spacing: 6) {
                    Text(kind.title)
                        .font(.title.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(kind.why)
                        .font(.body)
                        .captureSupportingText()
                        .fixedSize(horizontal: false, vertical: true)
                }

                captureArea
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .navigationTitle("Add photos")
        .onChange(of: pickerItem) {
            guard let pickerItem else { return }
            Task {
                if let data = try? await pickerItem.loadTransferable(type: Data.self),
                    let image = UIImage(data: data)
                {
                    model.setPhoto(image)
                }
                self.pickerItem = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-shoot")
    }

    /// "Shot n of 3" carries the progress semantics; the dots are decorative.
    private var progressHeader: some View {
        HStack(spacing: 10) {
            Text("Shot \(stepIndex + 1) of \(model.steps.count)")
                .font(.subheadline.weight(.semibold))
                .captureSupportingText()
            HStack(spacing: 6) {
                ForEach(Array(model.steps.enumerated()), id: \.element) { index, step in
                    Circle()
                        .strokeBorder(
                            index == stepIndex ? theme.primaryColor : .clear,
                            lineWidth: 2
                        )
                        .background(
                            Circle().fill(
                                model.result(for: step) != nil
                                    ? theme.primaryColor : Color(uiColor: .systemFill)
                            )
                            .padding(index == stepIndex ? 3 : 0)
                        )
                        .frame(width: 12, height: 12)
                }
            }
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var captureArea: some View {
        if case .photo(let image) = model.result(for: kind) {
            VStack(alignment: .leading, spacing: 12) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityLabel("Your photo of \(kind.title)")
                Label("Got it — \(kind.title)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.primaryColor)
                Button {
                    model.retakeCurrentShot()
                } label: {
                    Text("Retake")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("capture-retake")
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose a photo", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.primaryColor)
                .accessibilityIdentifier("capture-photo-picker")
                // Simulator stand-in for the camera; also what UI tests tap.
                Button {
                    model.setPhoto(CaptureSamplePhoto.image(for: kind))
                } label: {
                    Label("Use sample photo", systemImage: "camera.viewfinder")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                // Roast, not system blue: blue on the bordered gray fill is
                // ~3.4:1 and fails the contrast audit (bd#46 audit run).
                .tint(theme.primaryColor)
                .accessibilityIdentifier("capture-photo-sample")
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 240)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                model.advance()
            } label: {
                Text(model.advanceButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.primaryColor)
            .disabled(!model.canAdvance)
            .accessibilityIdentifier("capture-next")

            HStack(spacing: 8) {
                Button {
                    model.goBack()
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("capture-back")

                Button {
                    model.skipCurrentShot()
                } label: {
                    Text("Skip this shot")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("capture-skip")
            }
            .font(.subheadline)
            // Quiet actions, but in full-strength roast: dimmed gray fails
            // the contrast audit over the bar material (bd#46 audit run).
            .foregroundStyle(theme.primaryColor)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        // Solid theme background, not .bar: the audit's contrast check
        // cannot resolve text over blur materials and fails regardless of
        // the actual ratio (bd#46 audit run — roast on near-white flagged).
        .background(theme.backgroundColor)
    }
}
#endif
