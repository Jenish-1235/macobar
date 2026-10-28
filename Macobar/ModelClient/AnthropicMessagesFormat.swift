import Foundation

/// Anthropic's Messages API, spoken by Claude and Claude on Amazon Bedrock.
struct AnthropicMessagesFormat: WireFormat {
    /// Whether declined requests are retried server-side on another model (Claude API, default model only).
    let usesServerFallbacks: Bool

    /// The API version, plus the fallback beta when it's used.
    var formatHeaders: [String: String] {
        var headers = ["anthropic-version": "2023-06-01"]
        if usesServerFallbacks { headers["anthropic-beta"] = "server-side-fallback-2026-07-01" }
        return headers
    }

    /// A streamed Messages request. Thinking is left at the model's default (adaptive on current models).
    func requestBody(model: String, instructions: String, conversation: [ChatMessage]) throws -> Data {
        try encode(Body(
            model: model,
            maxTokens: 64_000,
            stream: true,
            system: instructions,
            messages: conversation.map { Message(role: $0.role, content: $0.text) },
            fallbacks: usesServerFallbacks ? "default" : nil
        ))
    }

    /// Text deltas become text; `message_stop` ends the reply; errors and refusals throw.
    func read(payload: String) throws -> StreamEvent {
        let event = try decode(Event.self, from: payload)
        switch event.type {
        case "content_block_delta" where event.delta?.type == "text_delta":
            return .text(event.delta?.text ?? "")
        case "message_delta" where event.delta?.stopReason == "refusal":
            throw ModelClientError.declined
        case "message_stop":
            return .finished
        case "error":
            throw ModelClientError.failed(event.error?.message ?? "The provider reported an error.")
        default:
            return .ignored
        }
    }

    /// Request body.
    private struct Body: Encodable {
        /// Model ID.
        let model: String
        /// Output ceiling; streaming keeps long replies from timing out.
        let maxTokens: Int
        /// Always streamed.
        let stream: Bool
        /// The system prompt.
        let system: String
        /// The conversation so far.
        let messages: [Message]
        /// `"default"` to retry declines on Anthropic's recommended model; omitted otherwise.
        let fallbacks: String?
    }

    /// One conversation turn.
    private struct Message: Encodable {
        /// Who said it.
        let role: ChatMessage.Role
        /// What was said.
        let content: String
    }

    /// The fields macobar reads from a streamed event.
    private struct Event: Decodable {
        /// Event type, e.g. `content_block_delta`.
        let type: String
        /// The change this event carries.
        let delta: Delta?
        /// Present on `error` events.
        let error: ProviderErrorDetail?

        /// A text delta or a message-level change.
        struct Delta: Decodable {
            /// Delta type, e.g. `text_delta`.
            let type: String?
            /// New reply text.
            let text: String?
            /// Why the reply stopped.
            let stopReason: String?

            /// Maps the API's snake_case keys.
            enum CodingKeys: String, CodingKey {
                case type, text
                case stopReason = "stop_reason"
            }
        }
    }
}
