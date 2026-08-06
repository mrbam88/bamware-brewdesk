import Foundation

struct ConversationParticipant: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case human
        case agent
    }

    let id: String
    let displayName: String
    let kind: Kind
}

struct ConversationMessage: Identifiable, Equatable, Sendable {
    enum Delivery: Equatable, Sendable {
        case sent
        case failed
    }

    let id: UUID
    let author: ConversationParticipant
    let text: String
    let sentAt: Date
    var delivery: Delivery

    init(
        id: UUID = UUID(),
        author: ConversationParticipant,
        text: String,
        sentAt: Date = Date(),
        delivery: Delivery = .sent
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.sentAt = sentAt
        self.delivery = delivery
    }
}

protocol ConversationTransport: Sendable {
    /// A human transport may return nil and deliver remote messages separately.
    /// An agent transport can return its immediate response.
    func send(text: String, threadID: String, senderID: String) async throws -> ConversationMessage?
}
