import Foundation
import Observation

@MainActor
@Observable
final class ConversationModel {
    private(set) var messages: [ConversationMessage]
    private(set) var isWaitingForReply = false
    private(set) var errorMessage: String?
    var draft = ""

    let threadID: String
    let currentUser: ConversationParticipant
    let otherParticipant: ConversationParticipant

    private let transport: any ConversationTransport

    init(
        threadID: String,
        currentUser: ConversationParticipant,
        otherParticipant: ConversationParticipant,
        messages: [ConversationMessage] = [],
        transport: any ConversationTransport
    ) {
        self.threadID = threadID
        self.currentUser = currentUser
        self.otherParticipant = otherParticipant
        self.messages = messages
        self.transport = transport
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWaitingForReply
    }

    func useSuggestion(_ suggestion: String) async {
        draft = suggestion
        await send()
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWaitingForReply else { return }

        draft = ""
        errorMessage = nil
        let outgoing = ConversationMessage(author: currentUser, text: text)
        messages.append(outgoing)
        isWaitingForReply = true
        defer { isWaitingForReply = false }

        do {
            if let reply = try await transport.send(
                text: text,
                threadID: threadID,
                senderID: currentUser.id
            ) {
                messages.append(reply)
            }
        } catch {
            if let index = messages.firstIndex(where: { $0.id == outgoing.id }) {
                messages[index].delivery = .failed
            }
            errorMessage = "Message not sent. Try again."
        }
    }
}
