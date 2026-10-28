import Foundation

/// OpenAI's Chat Completions API, spoken by Gemini, Azure OpenAI, OpenRouter and OpenCode Zen.
struct ChatCompletionsFormat: WireFormat {
    /// Authentication is all these providers need.
    var formatHeaders: [String: String] { [:] }

    /// A streamed request with the instructions as the first, system message.
    func requestBody(model: String, instructions: String, conversation: [ChatMessage]) throws -> Data {
        let system = Message(role: "system", content: instructions)
        let turns = conversation.map { Message(role: $0.role.rawValue, content: $0.text) }
        return try encode(Body(model: model, stream: true, messages: [system] + turns))
    }

    /// Content deltas become text; an `error` payload throws. `[DONE]` is handled by `read(line:)`.
    func read(payload: String) throws -> StreamEvent {
        let chunk = try decode(Chunk.self, from: payload)
        if let error = chunk.error { throw ModelClientError.failed(error.message ?? "The provider reported an error.") }
        guard let text = chunk.choices?.first?.delta?.content, !text.isEmpty else { return .ignored }
        return .text(text)
    }

    /// Request body.
    private struct Body: Encodable {
        /// Model ID; for Azure, the deployment name.
        let model: String
        /// Always streamed.
        let stream: Bool
        /// System message followed by the conversation.
        let messages: [Message]
    }

    /// One message.
    private struct Message: Encodable {
        /// `system`, `user` or `assistant`.
        let role: String
        /// What was said.
        let content: String
    }

    /// The fields macobar reads from a streamed chunk.
    private struct Chunk: Decodable {
        /// Usually one choice carrying the new text.
        let choices: [Choice]?
        /// Present when the provider fails mid-stream (OpenRouter does this).
        let error: ProviderErrorDetail?

        /// One completion choice.
        struct Choice: Decodable {
            /// The new part of the reply.
            let delta: Delta?
        }

        /// The new part of the reply.
        struct Delta: Decodable {
            /// New reply text.
            let content: String?
        }
    }
}
