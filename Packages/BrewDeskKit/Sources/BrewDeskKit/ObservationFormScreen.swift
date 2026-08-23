// Structured observation form — entry card + sheet UI (brewdesk#47, #79).
// Ships in Release (unlike the Debug-only capture prototype, #46): five enum
// questions, one tap each, no free text anywhere. Submit → thank-you;
// engine down → friendly error + Retry. Wire contract: venue-engine PR #26.
import SwiftUI
import VenueKit

// MARK: - Answer display vocabulary

/// UI titles for the wire enums. Copy lives here (the UI layer); the wire
/// values live in VenueKit — the two must never be conflated.
protocol ObservationAnswerOption: CaseIterable, Hashable, Sendable, RawRepresentable
where RawValue == String {
    var optionTitle: String { get }
}

extension LaptopFriendlyAnswer: ObservationAnswerOption {
    var optionTitle: String {
        switch self {
        case .yes: String(localized: "Yes")
        case .mixed: String(localized: "Mixed")
        case .no: String(localized: "No")
        }
    }
}

extension AvailabilityAnswer: ObservationAnswerOption {
    var optionTitle: String {
        switch self {
        case .noneAvailable: String(localized: "None")
        case .few: String(localized: "A few")
        case .plenty: String(localized: "Plenty")
        }
    }
}

extension NoiseAnswer: ObservationAnswerOption {
    var optionTitle: String {
        switch self {
        case .quiet: String(localized: "Quiet")
        case .moderate: String(localized: "Moderate")
        case .loud: String(localized: "Loud")
        }
    }
}

extension WifiQualityAnswer: ObservationAnswerOption {
    var optionTitle: String {
        switch self {
        case .fast: String(localized: "Fast")
        case .acceptable: String(localized: "OK")
        case .slow: String(localized: "Slow")
        case .unusable: String(localized: "Unusable")
        }
    }
}

/// Supporting copy: `.secondary` (and any translucent text) fails the
/// accessibility contrast audit on the oat background — verified on the
/// iPhone 17e audit runs for brewdesk#46. Fully opaque dynamic gray instead.
private extension View {
    func observationSupportingText() -> some View {
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

// MARK: - Entry card (venue detail)

/// "Rate this visit" card on the venue detail. Owns its sheet and resolves
/// its own service (environment override → `ObservationServiceResolver`), so
/// the detail screen's addition is a single line and the composition root
/// (RootView) is untouched.
public struct ObservationFormEntrySection: View {
    @Environment(\.venueObservationService) private var injectedService
    @Environment(\.colorScheme) private var colorScheme
    private let venue: Venue
    @State private var showForm = false

    public init(venue: Venue) {
        self.venue = venue
    }

    private var theme: BrewDeskTheme { BrewDeskTheme(isDarkMode: colorScheme == .dark) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Been here today?", systemImage: "person.2.wave.2")
                .font(.headline)
                .foregroundStyle(theme.primaryColor)
            Text("Five taps, no typing. Your answers become community claims — stamped with their source, like every claim above.")
                .font(.subheadline)
                .observationSupportingText()
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showForm = true
            } label: {
                Text("Rate this visit")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(BrewDeskPalette.roast)
            .accessibilityIdentifier("observation-entry")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrewDeskPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("observation-section")
        .sheet(isPresented: $showForm) {
            ObservationFormScreen(
                venue: venue,
                service: injectedService ?? ObservationServiceResolver.resolve()
            )
        }
    }
}

// MARK: - Form sheet

public struct ObservationFormScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var model: ObservationFormModel
    private let venueName: String

    public init(venue: Venue, service: any VenueObservationSubmitting) {
        venueName = venue.name
        _model = State(initialValue: ObservationFormModel(venueId: venue.id, service: service))
    }

    private var theme: BrewDeskTheme { BrewDeskTheme(isDarkMode: colorScheme == .dark) }

    public var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundColor.ignoresSafeArea()
                if model.phase == .submitted {
                    thanks
                } else {
                    questions
                }
            }
            .navigationTitle("Rate this visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.phase != .submitted {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                            .disabled(model.isSubmitting)
                            .accessibilityIdentifier("observation-cancel")
                    }
                }
            }
        }
        // Five taps are cheap to redo; only an in-flight submit must not be
        // torn down mid-request.
        .interactiveDismissDisabled(model.isSubmitting)
        // Submit outcome haptics (brewdesk#75): a light confirmation the tap
        // landed, distinct from the failure buzz on a friendly engine-down
        // error. `.sensoryFeedback` already no-ops under Reduce Motion.
        .sensoryFeedback(.success, trigger: model.phase) { _, new in
            if case .submitted = new { true } else { false }
        }
        .sensoryFeedback(.error, trigger: model.phase) { _, new in
            if case .failed = new { true } else { false }
        }
    }

    private var questions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How is \(venueName) right now? One tap per question.")
                    .font(.subheadline)
                    .observationSupportingText()
                    .fixedSize(horizontal: false, vertical: true)

                ObservationQuestionCard(
                    title: "Laptop-friendly today?",
                    systemImage: "laptopcomputer",
                    questionID: "laptop",
                    selection: model.laptopFriendly,
                    theme: theme
                ) { model.select(laptopFriendly: $0) }

                ObservationQuestionCard(
                    title: "Seats available?",
                    systemImage: "chair",
                    questionID: "seats",
                    selection: model.seats,
                    theme: theme
                ) { model.select(seats: $0) }

                ObservationQuestionCard(
                    title: "Outlets working?",
                    systemImage: "powerplug",
                    questionID: "outlets",
                    selection: model.outlets,
                    theme: theme
                ) { model.select(outlets: $0) }

                ObservationQuestionCard(
                    title: "How loud is it?",
                    systemImage: "speaker.wave.2",
                    questionID: "noise",
                    selection: model.noise,
                    theme: theme
                ) { model.select(noise: $0) }

                // brewdesk#79 — feeds the engine's wifi claim (user_report).
                ObservationQuestionCard(
                    title: "How's the Wi-Fi?",
                    systemImage: "wifi",
                    questionID: "wifi",
                    selection: model.wifiQuality,
                    theme: theme
                ) { model.select(wifiQuality: $0) }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) { submitArea }
    }

    private var submitArea: some View {
        VStack(spacing: 10) {
            if case .failed(let message) = model.phase {
                HStack(spacing: 10) {
                    Label(message, systemImage: "wifi.exclamationmark")
                        .font(.caption.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Retry") {
                        Task { await model.submit() }
                    }
                    .font(.caption.bold())
                    .accessibilityIdentifier("observation-retry")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .brewDeskGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("observation-error")
            }

            Button {
                Task { await model.submit() }
            } label: {
                // No explicit foreground color: `.borderedProminent` dims its
                // own label when disabled — forcing white here left white text
                // on the dimmed fill, a real (audit-caught) contrast failure.
                Group {
                    if model.isSubmitting {
                        ProgressView()
                    } else {
                        Text("Send")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(BrewDeskPalette.roast)
            .disabled(!model.isComplete || model.isSubmitting)
            .accessibilityIdentifier("observation-submit")
            .accessibilityHint(
                model.isComplete
                    ? Text("Sends your five answers")
                    : Text("Answer all five questions first")
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(theme.backgroundColor)
    }

    /// Thank-you state — provenance-consistent: says exactly where the
    /// answers land (community-sourced claims), moss seal like the human
    /// provenance stamp.
    private var thanks: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(BrewDeskPalette.moss)
                .accessibilityHidden(true)
            Text("Thanks for the report!")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("observation-thanks")
            Text("Your answers now appear as community-sourced claims on \(venueName) — right next to the curated and measured evidence.")
                .font(.body)
                .observationSupportingText()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(BrewDeskPalette.roast)
            .accessibilityIdentifier("observation-done")
            .padding(.top, 8)
        }
        .padding(24)
    }
}

// MARK: - Question card

/// One question, answered with a single tap on one of three options.
/// Custom segmented row (not `Picker.segmented`) so each option keeps a
/// ≥44 pt hit region, an explicit selected trait, and a stable
/// `observation-<question>-<wire value>` identifier for UI tests.
struct ObservationQuestionCard<Option: ObservationAnswerOption>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let questionID: String
    let selection: Option?
    let theme: BrewDeskTheme
    let onSelect: (Option) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(theme.primaryColor)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { options }
                VStack(spacing: 8) { options }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrewDeskPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("observation-question-\(questionID)")
    }

    private var options: some View {
        ForEach(Array(Option.allCases), id: \.self) { option in
            let isSelected = option == selection
            Button {
                onSelect(option)
            } label: {
                Text(option.optionTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        isSelected
                            ? (theme.isDarkMode ? BrewDeskPalette.espresso : Color.white)
                            : Color.primary
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .background(
                isSelected
                    ? AnyShapeStyle(theme.primaryColor)
                    : AnyShapeStyle(BrewDeskPalette.surfaceSecondary),
                in: Capsule()
            )
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("observation-\(questionID)-\(option.rawValue)")
        }
    }
}
