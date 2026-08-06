import Foundation

actor DemoAgentTransport: ConversationTransport {
    private let agent: ConversationParticipant

    init(agent: ConversationParticipant) {
        self.agent = agent
    }

    func send(text: String, threadID: String, senderID: String) async throws -> ConversationMessage? {
        try await Task.sleep(for: .milliseconds(700))
        let prompt = text.lowercased()
        let response: String

        if prompt.contains("quiet") {
            response = "I can narrow the map to quieter cafes. Do you also need fast Wi-Fi or plenty of outlets?"
        } else if prompt.contains("wifi") {
            response = "Fast Wi-Fi makes sense. Tell me your neighborhood and whether laptop-friendly seating is required."
        } else if prompt.contains("outlet") {
            response = "I’ll prioritize cafes with plenty of outlets. How far are you willing to travel?"
        } else {
            response = "I can help turn that into cafe filters. What neighborhood, noise level, and work setup do you prefer?"
        }

        return ConversationMessage(author: agent, text: response)
    }
}
