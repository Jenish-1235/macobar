/// One turn of a conversation with a model.
struct ChatMessage: Equatable, Sendable {
    /// Who said it.
    enum Role: String, Encodable, Sendable {
        case user
        case assistant
    }

    /// Who said it.
    let role: Role
    /// What was said.
    let text: String
}
