// Ask tab (bamware-brewdesk#247): a grounded café chat over the engine's
// `POST /v1/chat`. Transcript of bubbles, venue cards under each reply that
// open the existing detail screen, a pinned composer, and one inline row per
// `ChatError`. Palette: `BrewDeskPalette` tokens only — nothing here is
// red-vs-green as a lone signal (founder is red-green colorblind).
import BamwareAccounts
import BamwareAccountUI
import SwiftUI
import VenueKit

public struct AskScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.launchEnvironment) private var launchEnvironment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let model: ChatModel
    let savedVenues: SavedVenuesStore

    @State private var draft = ""
    @FocusState private var isComposerFocused: Bool
    /// Lazily built the first time a sign-in row appears — same
    /// fresh-per-surface pattern `ObservationFormScreen` uses (bd#202): it
    /// reads the shared keychain, so a sign-in here is visible everywhere.
    @State private var accountModel: AccountModel?
    @State private var isSignInPresented = false

    public init(model: ChatModel, savedVenues: SavedVenuesStore) {
        self.model = model
        self.savedVenues = savedVenues
    }

    private var theme: BrewDeskTheme { BrewDeskTheme(isDarkMode: colorScheme == .dark) }

    private static let bottomAnchor = "ask-bottom"

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.transcript.isEmpty, model.phase == .idle {
                        emptyState
                    } else {
                        ForEach(model.transcript) { entry in
                            TranscriptRow(entry: entry)
                        }
                        statusRow
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.transcript.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: model.phase) { _, _ in
                scrollToBottom(proxy)
            }
        }
        .background(BrewDeskPalette.page.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationTitle("Ask")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Venue.self) { venue in
            VenueDetailScreen(venue: venue, savedVenues: savedVenues)
        }
        .onChange(of: accountModel?.sessions.isSignedIn) { _, isSignedIn in
            guard isSignedIn == true, model.phase == .failed(.signInRequired) else { return }
            isSignInPresented = false
            Task { await model.retry() }
        }
        .sheet(isPresented: $isSignInPresented) {
            NavigationStack { signInSheetContent }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    private func send(_ text: String) {
        let message = text
        draft = ""
        Task { await model.send(message) }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What do you need today?")
                    .font(BrewDeskFont.headline(.title2))
                Text("Describe the spot you're after. Answers come from BrewDesk's own data.")
                    .font(.subheadline)
                    .foregroundStyle(BrewDeskPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ask-empty-state")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(ChatModel.suggestions.enumerated()), id: \.element) { index, suggestion in
                    Button {
                        send(suggestion)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkle")
                                .font(.caption)
                                .foregroundStyle(BrewDeskPalette.primaryText)
                            Text(suggestion)
                                .font(BrewDeskFont.label(.subheadline))
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(BrewDeskPalette.surfaceSecondary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ask-suggestion-\(index)")
                }
            }
        }
        .padding(.top, 24)
    }

    // MARK: - Status row (thinking / error)

    @ViewBuilder
    private var statusRow: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .sending:
            AssistantBubble {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(BrewDeskPalette.primaryText)
                    Text("Thinking…")
                        .font(.subheadline)
                        .foregroundStyle(BrewDeskPalette.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ask-sending")
        case .failed(let error):
            errorRow(error)
        }
    }

    private func errorRow(_ error: ChatError) -> some View {
        AssistantBubble {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: errorSymbol(error))
                        .foregroundStyle(BrewDeskPalette.secondaryText)
                    Text(error.userMessage)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(errorIdentifier(error))
                }
                if error.isRetryable {
                    Button("Retry") {
                        Task { await model.retry() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrewDeskPalette.roast)
                    .accessibilityIdentifier("ask-retry")
                } else if error == .signInRequired {
                    Button("Sign in") {
                        isSignInPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrewDeskPalette.roast)
                    .accessibilityIdentifier("ask-sign-in")
                    .task {
                        if accountModel == nil {
                            accountModel = BrewDeskAccountStack.makeModel(environment: launchEnvironment)
                        }
                    }
                }
            }
        }
    }

    private func errorSymbol(_ error: ChatError) -> String {
        switch error {
        case .signInRequired: "person.crop.circle.badge.questionmark"
        case .disabled: "moon.zzz"
        case .dailyCap: "hourglass"
        case .upstream, .offline: "wifi.exclamationmark"
        }
    }

    private func errorIdentifier(_ error: ChatError) -> String {
        switch error {
        case .signInRequired: "ask-sign-in-required"
        case .disabled: "ask-state-disabled"
        case .dailyCap: "ask-state-daily-cap"
        case .upstream, .offline: "ask-state-unreachable"
        }
    }

    // MARK: - Composer

    private var sendDisabled: Bool {
        model.isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField("Ask about a spot…", text: $draft)
                .textFieldStyle(.plain)
                .focused($isComposerFocused)
                .submitLabel(.send)
                .onSubmit {
                    guard !sendDisabled else { return }
                    send(draft)
                }
                .onChange(of: draft) { _, value in
                    if value.count > ChatRequest.maxMessageLength {
                        draft = String(value.prefix(ChatRequest.maxMessageLength))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(BrewDeskPalette.surface, in: Capsule())
                .overlay(Capsule().stroke(BrewDeskPalette.surfaceSecondary, lineWidth: 1))
                .accessibilityIdentifier("ask-input")

            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .foregroundStyle(sendDisabled ? BrewDeskPalette.unobserved : BrewDeskPalette.roast)
            .disabled(sendDisabled)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("ask-send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(BrewDeskPalette.page)
    }

    // MARK: - Sign-in sheet

    @ViewBuilder
    private var signInSheetContent: some View {
        if let accountModel {
            VStack(alignment: .leading, spacing: 0) {
                Text("Sign in to ask")
                    .font(.title3.bold())
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                SignInScreen(model: accountModel, theme: theme)
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isSignInPresented = false }
                }
            }
        } else {
            ProgressView()
        }
    }
}

// MARK: - Rows

/// One transcript entry: a trailing user bubble, or a leading assistant
/// bubble followed by its venue cards.
private struct TranscriptRow: View {
    let entry: ChatTranscriptEntry

    var body: some View {
        switch entry.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(entry.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(BrewDeskPalette.roast, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityIdentifier("ask-user-message")
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                AssistantBubble {
                    Text(entry.text)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ask-reply")
                }
                ForEach(entry.venues) { venue in
                    NavigationLink(value: venue) {
                        AskVenueCard(venue: venue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("ask-venue-card-\(venue.id)")
                }
            }
        }
    }
}

/// Leading bubble on `surface` — shared by replies, the thinking indicator,
/// and error rows so they read as one voice.
private struct AssistantBubble<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(BrewDeskPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(BrewDeskPalette.surfaceSecondary, lineWidth: 1)
                )
            Spacer(minLength: 32)
        }
    }
}

/// Compact venue card under a reply: name, neighborhood (+ distance when the
/// engine computed one, + type badge for non-cafés), and the existing
/// `ScoreBadge` so the honest "Not rated yet" state renders identically here.
private struct AskVenueCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let venue: Venue

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(venue.name)
                    .font(BrewDeskFont.headline(.subheadline))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                HStack(spacing: 8) {
                    Text(venue.neighborhood)
                    if let meters = venue.distanceM {
                        Text(verbatim: "·")
                        Text(Self.distance(meters))
                    }
                    VenueTypeBadgeView(type: venue.typeBadge)
                }
                .font(.caption)
                .foregroundStyle(BrewDeskPalette.secondaryText)
            }
            Spacer(minLength: 8)
            ScoreBadge(venue: venue)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BrewDeskPalette.secondaryText)
        }
        .padding(12)
        .background(BrewDeskPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BrewDeskPalette.surfaceSecondary, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static func distance(_ meters: Int) -> String {
        Measurement(value: Double(meters), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
