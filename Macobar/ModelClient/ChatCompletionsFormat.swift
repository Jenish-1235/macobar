import Foundation

/// OpenAI's Chat Completions API, spoken by Gemini, Azure OpenAI, OpenRouter and OpenCode Zen.
struct ChatCompletionsFormat: WireFormat {
    /// Authentication is all these providers need.
    var formatHeaders: [String: String] { [:] }

    /// A streamed request with the instructions as the first, system message.
    func requestBody(model: String, instructions: String, conversation: [ConversationItem], tools: [ToolDefinition]) throws -> Data {
        let system: JSONValue = ["role": "system", "content": .string(instructions)]
        var body: [String: JSONValue] = [
            "model": .string(model),
            "stream": true,
            "messages": .array([system] + conversation.flatMap(messages)),
        ]
        if !tools.isEmpty {
            body["tools"] = .array(tools.map { tool in
                ["type": "function", "function": ["name": .string(tool.name), "description": .string(tool.description), "parameters": tool.parameters]]
            })
        }
        return try JSONValue.object(body).encoded()
    }

    /// A reader for Chat Completions chunks.
    func makeReader() -> any ReplyReader {
        ChatCompletionsReplyReader()
    }

    /// One conversation item as chat messages; tool results become one message each, plus one user message carrying their images.
    private func messages(_ item: ConversationItem) -> [JSONValue] {
        switch item {
        case .user(let text):
            return [["role": "user", "content": .string(text)]]
        case .assistant(let turn):
            var message: [String: JSONValue] = ["role": "assistant", "content": turn.text.isEmpty ? nil : .string(turn.text)]
            if !turn.toolCalls.isEmpty { message["tool_calls"] = .array(turn.toolCalls.map(toolCall)) }
            return [.object(message)]
        case .toolResults(let results):
            let toolMessages: [JSONValue] = results.map { result in
                ["role": "tool", "tool_call_id": .string(result.callID), "content": .string(result.isError ? "Error: \(result.output)" : result.output)]
            }
            return toolMessages + Self.imageMessage(for: results)
        }
    }

    /// Tool messages can't hold images, so any the tools returned follow in one user message; none when there are no images.
    private static func imageMessage(for results: [ToolResult]) -> [JSONValue] {
        let images: [JSONValue] = results.flatMap(\.images).map { ["type": "image_url", "image_url": ["url": .string($0.dataURL)]] }
        guard !images.isEmpty else { return [] }
        return [["role": "user", "content": .array([["type": "text", "text": "Images from the tool results above."]] + images)]]
    }

    /// A tool call as sent back, with any provider extras (Gemini's thought signature) restored.
    private func toolCall(_ call: ToolCall) -> JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(call.id),
            "type": "function",
            "function": ["name": .string(call.name), "arguments": .string(call.arguments)],
        ]
        if let extra = call.providerExtra { object["extra_content"] = extra }
        return .object(object)
    }
}

/// Collects text and tool-call fragments from Chat Completions chunks.
struct ChatCompletionsReplyReader: ReplyReader {
    /// One tool call being assembled from fragments.
    private struct PartialCall {
        /// The call's ID.
        var id = ""
        /// The tool's name.
        var name = ""
        /// Argument JSON received so far.
        var arguments = ""
        /// Provider extras attached to the call.
        var extra: JSONValue?
    }

    /// Reply text so far.
    private var text = ""
    /// Tool calls by their stream index.
    private var calls: [Int: PartialCall] = [:]
    /// Chat Completions ends with `[DONE]`, which `ModelClient` handles.
    let isFinished = false

    /// Applies one chunk, returning new reply text.
    mutating func read(payload: String) throws -> String? {
        let chunk = try JSONValue.parse(payload)
        if let error = chunk["error"] {
            throw ModelClientError.streamError(message: error["message"]?.string, code: error["code"]?.string, payload: payload)
        }
        guard let choice = chunk["choices"]?.array?.first else { return nil }
        if choice["finish_reason"]?.string == "length" { throw replyCutShort }
        for (position, fragment) in (choice["delta"]?["tool_calls"]?.array ?? []).enumerated() {
            let index = fragment["index"]?.number.flatMap { Int(exactly: $0.rounded(.towardZero)) } ?? position
            var call = calls[index] ?? PartialCall()
            call.id += fragment["id"]?.string ?? ""
            call.name += fragment["function"]?["name"]?.string ?? ""
            call.arguments += fragment["function"]?["arguments"]?.string ?? ""
            call.extra = fragment["extra_content"] ?? call.extra
            calls[index] = call
        }
        guard let delta = choice["delta"]?["content"]?.string, !delta.isEmpty else { return nil }
        text += delta
        return delta
    }

    /// The turn's text and tool calls, in stream order.
    func finishedTurn() throws -> AssistantTurn {
        let toolCalls = calls.keys.sorted().compactMap { calls[$0] }.map { call in
            ToolCall(id: call.id, name: call.name, arguments: call.arguments.isEmpty ? "{}" : call.arguments, providerExtra: call.extra)
        }
        return AssistantTurn(text: text, toolCalls: toolCalls)
    }
}
