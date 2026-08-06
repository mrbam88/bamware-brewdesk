import SwiftUI

struct ConversationScreen: View {
    @State private var model: ConversationModel
    @FocusState private var composerFocused: Bool

    private let suggestions = [
        "Find a quiet cafe",
        "I need fast Wi-Fi",
        "Show cafes with outlets",
    ]

    init(currentUser: ConversationParticipant) {
        let agent = ConversationParticipant(
            id: "cafe-guide",
            displayName: "Cafe Guide",
            kind: .agent
        )
        let welcome = ConversationMessage(
            author: agent,
            text: "Tell me what kind of work session you’re planning, and I’ll help shape the search."
        )
        self._model = State(initialValue: ConversationModel(
            threadID: "cafe-guide",
            currentUser: currentUser,
            otherParticipant: agent,
            messages: [welcome],
            transport: DemoAgentTransport(agent: agent)
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        threadIntro
                        ForEach(model.messages) { message in
                            MessageBubble(
                                message: message,
                                isCurrentUser: message.author.id == model.currentUser.id
                            )
                            .id(message.id)
                        }
                        if model.isWaitingForReply {
                            typingIndicator
                                .id("typing")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(AppBrand.oat.opacity(0.55))
                .safeAreaInset(edge: .bottom) { composer }
                .onChange(of: model.messages.count) {
                    scrollToLatest(proxy)
                }
                .onChange(of: model.isWaitingForReply) {
                    scrollToLatest(proxy)
                }
            }
            .navigationTitle(model.otherParticipant.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { statusToolbar }
        }
    }

    private var threadIntro: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppBrand.moss.opacity(0.14))
                    .frame(width: 64, height: 64)
                Image(systemName: "sparkles")
                    .font(.title2.bold())
                    .foregroundStyle(AppBrand.moss)
            }
            Text("Start with the outcome")
                .font(.headline)
            Text("Use the same thread with a person or an AI guide. Ask for a recommendation, compare options, or describe your ideal work session.")
                .font(.caption)
                .foregroundStyle(AppBrand.muted)
                .multilineTextAlignment(.center)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            Task { await model.useSuggestion(suggestion) }
                        }
                        .font(.caption.bold())
                        .foregroundStyle(AppBrand.roast)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(AppBrand.foam, in: Capsule())
                        .overlay(Capsule().stroke(AppBrand.roast.opacity(0.12)))
                        .disabled(model.isWaitingForReply)
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var typingIndicator: some View {
        HStack(alignment: .bottom, spacing: 8) {
            participantAvatar(model.otherParticipant)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(AppBrand.muted.opacity(0.55))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppBrand.foam, in: Capsule())
            Spacer(minLength: 64)
        }
        .accessibilityLabel("Cafe Guide is responding")
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppBrand.clay)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message or prompt", text: $model.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(AppBrand.foam, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppBrand.espresso.opacity(0.10)))
                    .accessibilityIdentifier("conversation-composer")

                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.bold())
                        .foregroundStyle(AppBrand.foam)
                        .frame(width: 44, height: 44)
                        .background(model.canSend ? AppBrand.espresso : AppBrand.muted.opacity(0.35), in: Circle())
                }
                .disabled(!model.canSend)
                .accessibilityLabel("Send message")
                .accessibilityIdentifier("conversation-send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }

    @ToolbarContentBuilder
    private var statusToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(model.otherParticipant.displayName)
                    .font(.headline)
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                    Text("Prototype agent")
                }
                    .font(.caption2)
                    .foregroundStyle(AppBrand.moss)
            }
        }
    }

    private func participantAvatar(_ participant: ConversationParticipant) -> some View {
        ZStack {
            Circle()
                .fill(participant.kind == .agent ? AppBrand.moss : AppBrand.clay)
            Image(systemName: participant.kind == .agent ? "sparkles" : "person.fill")
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if model.isWaitingForReply {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let id = model.messages.last?.id {
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }
}

private struct MessageBubble: View {
    let message: ConversationMessage
    let isCurrentUser: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isCurrentUser { Spacer(minLength: 54) }
            if !isCurrentUser { avatar }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 5) {
                if !isCurrentUser {
                    HStack(spacing: 4) {
                        Text(message.author.displayName)
                        if message.author.kind == .agent {
                            Image(systemName: "sparkles")
                        }
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(AppBrand.moss)
                }

                Text(message.text)
                    .font(.body)
                    .foregroundStyle(isCurrentUser ? AppBrand.foam : AppBrand.espresso)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        isCurrentUser ? AppBrand.espresso : AppBrand.foam,
                        in: RoundedRectangle(cornerRadius: 19)
                    )
                    .overlay {
                        if !isCurrentUser {
                            RoundedRectangle(cornerRadius: 19)
                                .stroke(AppBrand.espresso.opacity(0.08))
                        }
                    }

                HStack(spacing: 5) {
                    Text(message.sentAt, format: .dateTime.hour().minute())
                    if message.delivery == .failed {
                        Label("Failed", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(AppBrand.clay)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(AppBrand.muted)
            }

            if !isCurrentUser { Spacer(minLength: 54) }
        }
        .frame(maxWidth: .infinity)
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(message.author.kind == .agent ? AppBrand.moss : AppBrand.clay)
            Image(systemName: message.author.kind == .agent ? "sparkles" : "person.fill")
                .font(.caption2.bold())
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}
