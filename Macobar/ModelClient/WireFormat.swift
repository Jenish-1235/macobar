import Foundation

/// One request and response shape a provider speaks: how to ask, and how to read the streamed answer.
protocol WireFormat: Sendable {
    /// Headers this format needs besides authentication.
    var formatHeaders: [String: String] { get }
    /// The JSON body asking `model` to continue `conversation`, guided by `instructions`, with `tools` available.
    func requestBody(model: String, instructions: String, conversation: [ConversationItem], tools: [ToolDefinition]) throws -> Data
    /// A fresh reader for one streamed reply.
    func makeReader() -> any ReplyReader
}

/// Assembles one assistant turn from a streamed reply, one `data:` payload at a time.
protocol ReplyReader {
    /// Whether the provider signalled the end of the reply.
    var isFinished: Bool { get }
    /// Reads one payload and returns any new reply text.
    mutating func read(payload: String) throws -> String?
    /// The complete turn: text, tool calls, and the provider's own form for replay.
    func finishedTurn() throws -> AssistantTurn
}

extension ProviderAccount {
    /// The wire format this account's provider speaks.
    var wireFormat: any WireFormat {
        switch kind.apiFormat {
        case .anthropicMessages:
            AnthropicMessagesFormat(isClaudeAPI: kind == .claude, usesServerFallbacks: kind == .claude && model == kind.defaultModel)
        case .openAIChatCompletions: ChatCompletionsFormat()
        case .openAIResponses: ResponsesFormat()
        }
    }
}

extension JSONValue {
    /// Parses a tool call's argument string, falling back to an empty object so a bad call can still be replayed.
    static func arguments(_ text: String) -> JSONValue {
        (try? parse(text)).flatMap { $0.object == nil ? nil : $0 } ?? [:]
    }
}

/// Thrown when a reply stops at the provider's length limit, so half-written tool calls are never run.
let replyCutShort = ModelClientError.failed("The reply hit the model's length limit before it finished.")
