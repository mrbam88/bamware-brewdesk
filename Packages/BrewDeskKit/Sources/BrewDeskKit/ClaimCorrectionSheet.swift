// Single-claim correction — the compact sheet (brewdesk#251).
// One question (the same one, with the same answer choices, the full
// "Rate this visit" form asks) and a Submit button. Failure keeps the sheet
// with the form's friendly retry copy; a session with no token asks for
// sign-in exactly like the form does.
import BamwareAccounts
import BamwareAccountUI
import SwiftUI
import VenueKit

extension CorrectableClaim {
    /// Row title on the Workability card — also the `ClaimRow` title key.
    var rowTitle: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .outlets: "Outlets"
        case .laptopPolicy: "Laptop policy"
        case .noise: "Noise"
        case .seating: "Seating"
        }
    }

    var systemImage: String {
        switch self {
        case .wifi: "wifi"
        case .outlets: "powerplug"
        case .laptopPolicy: "laptopcomputer"
        case .noise: "speaker.wave.2"
        case .seating: "chair"
        }
    }

    /// The question the five-question form asks for this claim — the same
    /// wording as `ObservationFormScreen`'s cards, kept in step by hand.
    var questionTitle: LocalizedStringKey {
        switch self {
        case .wifi: "How's the Wi-Fi?"
        case .outlets: "Outlets working?"
        case .laptopPolicy: "Laptop-friendly today?"
        case .noise: "How loud is it?"
        case .seating: "Seats available?"
        }
    }

    /// Stable id fragment: `observation-<questionID>-<wire value>` matches
    /// the form's option identifiers.
    var questionID: String {
        switch self {
        case .wifi: "wifi"
        case .outlets: "outlets"
        case .laptopPolicy: "laptop"
        case .noise: "noise"
        case .seating: "seats"
        }
    }
}

struct ClaimCorrectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.launchEnvironment) private var launchEnvironment
    @State private var model: ClaimCorrectionModel
    @State private var accountModel: AccountModel?
    private let venueName: String
    private let currentValue: String?
    private let onCorrected: (Venue) -> Void

    init(
        venue: Venue,
        claim: CorrectableClaim,
        service: any VenueObservationSubmitting,
        onCorrected: @escaping (Venue) -> Void
    ) {
        venueName = venue.name
        currentValue = claim.claim(in: venue.attributes).map { localizedAttributeValue($0.value) }
        self.onCorrected = onCorrected
        _model = State(
            initialValue: ClaimCorrectionModel(venueId: venue.id, claim: claim, service: service)
        )
    }

    private var theme: BrewDeskTheme { BrewDeskTheme(isDarkMode: colorScheme == .dark) }

    private var isSignInPromptPresented: Binding<Bool> {
        Binding(
            get: { model.phase == .signInRequired },
            set: { presented in if !presented { model.cancelSignInPrompt() } }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(contextLine)
                        .font(.subheadline)
                        .foregroundStyle(BrewDeskPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("claim-correction-context")
                    question
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .background(theme.backgroundColor.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { submitArea }
            .navigationTitle("Not right?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(model.isSubmitting)
                        .accessibilityIdentifier("claim-correction-cancel")
                }
            }
        }
        .accessibilityIdentifier("claim-correction-sheet")
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(model.isSubmitting)
        .sensoryFeedback(.error, trigger: model.phase) { _, new in
            if case .failed = new { true } else { false }
        }
        .onChange(of: model.phase) { _, phase in
            // Success: hand the engine's response to the detail screen (it
            // refreshes the row and says thanks) and get out of the way.
            guard phase == .submitted, let venue = model.updatedVenue else { return }
            onCorrected(venue)
            dismiss()
        }
        // Same sign-in detour as the five-question form (bd#202, #249).
        .task {
            if accountModel == nil {
                accountModel = BrewDeskAccountStack.makeModel(environment: launchEnvironment)
            }
        }
        .onChange(of: accountModel?.sessions.isSignedIn) { _, isSignedIn in
            guard isSignedIn == true, model.phase == .signInRequired else { return }
            Task { await model.submit() }
        }
        .sheet(isPresented: isSignInPromptPresented) {
            NavigationStack { signInPromptContent }
        }
    }

    private var contextLine: String {
        guard let currentValue else {
            return String(localized: "Tell us what you found at \(venueName).")
        }
        let title = String(localized: String.LocalizationValue(model.claim.rowTitle))
        return String(localized: "\(venueName) shows \(title) as \(currentValue). Tell us what you found.")
    }

    @ViewBuilder
    private var question: some View {
        let claim = model.claim
        switch claim {
        case .wifi:
            card(selection: wifiSelection) { model.select(.wifiQuality($0)) }
        case .outlets:
            card(selection: outletsSelection) { model.select(.outletsWorking($0)) }
        case .laptopPolicy:
            card(selection: laptopSelection) { model.select(.laptopFriendlyToday($0)) }
        case .noise:
            card(selection: noiseSelection) { model.select(.noise($0)) }
        case .seating:
            card(selection: seatsSelection) { model.select(.seatsAvailable($0)) }
        }
    }

    private func card<Option: ObservationAnswerOption>(
        selection: Option?,
        onSelect: @escaping (Option) -> Void
    ) -> some View {
        ObservationQuestionCard(
            title: model.claim.questionTitle,
            systemImage: model.claim.systemImage,
            questionID: model.claim.questionID,
            selection: selection,
            theme: theme,
            onSelect: onSelect
        )
    }

    private var wifiSelection: WifiQualityAnswer? {
        if case .wifiQuality(let answer) = model.selection { answer } else { nil }
    }

    private var outletsSelection: AvailabilityAnswer? {
        if case .outletsWorking(let answer) = model.selection { answer } else { nil }
    }

    private var laptopSelection: LaptopFriendlyAnswer? {
        if case .laptopFriendlyToday(let answer) = model.selection { answer } else { nil }
    }

    private var noiseSelection: NoiseAnswer? {
        if case .noise(let answer) = model.selection { answer } else { nil }
    }

    private var seatsSelection: AvailabilityAnswer? {
        if case .seatsAvailable(let answer) = model.selection { answer } else { nil }
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
                    .accessibilityIdentifier("claim-correction-retry")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .brewDeskGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("claim-correction-error")
            }

            Button {
                Task { await model.submit() }
            } label: {
                Group {
                    if model.isSubmitting {
                        ProgressView()
                    } else {
                        Text("Submit")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(BrewDeskPalette.roast)
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("claim-correction-submit")
            .accessibilityHint(
                model.selection == nil
                    ? Text("Pick an answer first")
                    : Text("Sends this one correction")
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(theme.backgroundColor)
    }

    @ViewBuilder
    private var signInPromptContent: some View {
        if let accountModel {
            VStack(alignment: .leading, spacing: 0) {
                Text("Sign in to submit")
                    .font(.title3.bold())
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("claim-correction-sign-in-required")
                SignInScreen(model: accountModel, theme: theme)
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { model.cancelSignInPrompt() }
                }
            }
        } else {
            ProgressView()
        }
    }
}
