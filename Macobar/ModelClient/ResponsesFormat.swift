import Foundation

/// OpenAI's Responses API, spoken by OpenAI and required for ChatGPT plan usage.
struct ResponsesFormat: WireFormat {
    /// Authentication is all OpenAI needs.
    var formatHeaders: [String: String] { [:] }

    /// A streamed, unstored request; ChatGPT sign-in rejects anything else.
    func requestBody(model: String, instructions: String, conversation: [ChatMessage]) throws -> Data {
        try encode(Body(
            model: model,
            stream: true,
            store: false,
            instructions: instructions,
            input: conversation.map { Message(role: $0.role, content: $0.text) }
        ))
    }

    /// Output text deltas become text; `response.completed` ends the reply; failures throw.
    func read(payload: String) throws -> StreamEvent {
        let event = try decode(Event.self, from: payload)
        switch event.type {
        case "response.output_text.delta": return .text(event.delta ?? "")
        case "response.completed": return .finished
        case "response.failed", "error":
            throw ModelClientError.failed(event.response?.error?.message ?? event.message ?? "The provider reported an error.")
        case "response.incomplete":
            throw ModelClientError.failed("The reply was cut short (\(event.response?.incompleteDetails?.reason ?? "unknown reason")).")
        default: return .ignored
        }
    }

    /// Request body.
    private struct Body: Encodable {
        /// Model ID.
        let model: String
        /// Always streamed.
        let stream: Bool
        /// Never kept on OpenAI's servers.
        let store: Bool
        /// The system prompt.
        let instructions: String
        /// The conversation so far.
        let input: [Message]
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
        /// Event type, e.g. `response.output_text.delta`.
        let type: String
        /// New reply text on delta events.
        let delta: String?
        /// Error text on `error` events.
        let message: String?
        /// The response, on completion and failure events.
        let response: Response?

        /// The parts of a finished or failed response macobar reads.
        struct Response: Decodable {
            /// Why the response failed.
            let error: ProviderErrorDetail?
            /// Why the response stopped early.
            let incompleteDetails: IncompleteDetails?

            /// Maps the API's snake_case keys.
            enum CodingKeys: String, CodingKey {
                case error
                case incompleteDetails = "incomplete_details"
            }
        }

        /// Why a response stopped early.
        struct IncompleteDetails: Decodable {
            /// E.g. `max_output_tokens` or `content_filter`.
            let reason: String?
        }
    }
}
