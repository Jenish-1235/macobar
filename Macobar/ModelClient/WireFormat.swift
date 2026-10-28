import Foundation

/// One request and response shape a provider speaks: how to ask, and how to read the streamed answer.
protocol WireFormat: Sendable {
    /// Headers this format needs besides authentication.
    var formatHeaders: [String: String] { get }
    /// The JSON body asking `model` to continue `conversation`, guided by `instructions`.
    func requestBody(model: String, instructions: String, conversation: [ChatMessage]) throws -> Data
    /// Reads the JSON payload of one streamed `data:` line.
    func read(payload: String) throws -> StreamEvent
}

/// What one streamed line meant.
enum StreamEvent: Equatable, Sendable {
    /// More reply text.
    case text(String)
    /// The reply is complete.
    case finished
    /// Bookkeeping that carries no reply text.
    case ignored
}

extension WireFormat {
    /// Reads one line of a server-sent event stream; only `data:` lines carry anything.
    func read(line: String) throws -> StreamEvent {
        guard line.hasPrefix("data:") else { return .ignored }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]" else { return .finished }
        return try read(payload: payload)
    }

    /// Encodes a request body, turning Swift's camelCase names into the APIs' snake_case keys.
    func encode(_ body: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(body)
    }

    /// Decodes a streamed JSON payload into `type`.
    func decode<Payload: Decodable>(_ type: Payload.Type, from payload: String) throws -> Payload {
        try JSONDecoder().decode(type, from: Data(payload.utf8))
    }
}

extension ProviderAccount {
    /// The wire format this account's provider speaks.
    var wireFormat: any WireFormat {
        switch kind.apiFormat {
        case .anthropicMessages: AnthropicMessagesFormat(usesServerFallbacks: kind == .claude && model == kind.defaultModel)
        case .openAIChatCompletions: ChatCompletionsFormat()
        case .openAIResponses: ResponsesFormat()
        }
    }
}
