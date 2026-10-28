import Foundation

/// OpenAI's Responses API, spoken by OpenAI and required for ChatGPT plan usage.
struct ResponsesFormat: WireFormat {
    /// Authentication is all OpenAI needs.
    var formatHeaders: [String: String] { [:] }

    /// A streamed, unstored request; reasoning comes back encrypted so it can be replayed in later steps.
    func requestBody(model: String, instructions: String, conversation: [ConversationItem], tools: [ToolDefinition]) throws -> Data {
        var body: [String: JSONValue] = [
            "model": .string(model),
            "stream": true,
            "store": false,
            "instructions": .string(instructions),
            "input": .array(conversation.flatMap(inputItems)),
            "include": ["reasoning.encrypted_content"],
        ]
        if !tools.isEmpty {
            body["tools"] = .array(tools.map { tool in
                ["type": "function", "name": .string(tool.name), "description": .string(tool.description), "parameters": tool.parameters]
            })
        }
        return try JSONValue.object(body).encoded()
    }

    /// A reader for Responses stream events.
    func makeReader() -> any ReplyReader {
        ResponsesReplyReader()
    }

    /// One conversation item as Responses input items.
    private func inputItems(_ item: ConversationItem) -> [JSONValue] {
        switch item {
        case .user(let text):
            return [["role": "user", "content": .string(text)]]
        case .assistant(let turn):
            if let native = turn.nativeContent?.array { return native }
            let message: [JSONValue] = turn.text.isEmpty ? [] : [["role": "assistant", "content": .string(turn.text)]]
            return message + turn.toolCalls.map { call in
                ["type": "function_call", "call_id": .string(call.id), "name": .string(call.name), "arguments": .string(call.arguments)]
            }
        case .toolResults(let results):
            return results.map { result in
                ["type": "function_call_output", "call_id": .string(result.callID), "output": Self.output(of: result)]
            }
        }
    }

    /// A tool result's output: plain text, or a text part followed by image parts when the tool returned images.
    private static func output(of result: ToolResult) -> JSONValue {
        let text = result.isError ? "Error: \(result.output)" : result.output
        guard !result.images.isEmpty else { return .string(text) }
        let images: [JSONValue] = result.images.map { ["type": "input_image", "image_url": .string($0.dataURL)] }
        return .array([["type": "input_text", "text": .string(text)]] + images)
    }
}

/// Collects text and finished output items from Responses stream events.
struct ResponsesReplyReader: ReplyReader {
    /// Reply text so far.
    private var text = ""
    /// Finished output items, prepared for replay.
    private var items: [JSONValue] = []
    /// Tool calls among the output items.
    private var toolCalls: [ToolCall] = []
    /// Whether `response.completed` arrived.
    private(set) var isFinished = false

    /// Applies one event, returning new reply text.
    mutating func read(payload: String) throws -> String? {
        let event = try JSONValue.parse(payload)
        switch event["type"]?.string {
        case "response.output_text.delta":
            let delta = event["delta"]?.string ?? ""
            text += delta
            return delta
        case "response.output_item.done":
            if let item = event["item"] { record(item) }
        case "response.completed":
            isFinished = true
        case "response.incomplete":
            if event["response"]?["incomplete_details"]?["reason"]?.string == "max_output_tokens" { throw replyCutShort }
            throw ModelClientError.failed("The reply was cut short (\(event["response"]?["incomplete_details"]?["reason"]?.string ?? "unknown reason")).")
        case "response.failed", "error":
            let error = event["response"]?["error"] ?? event["error"] ?? event
            throw ModelClientError.streamError(message: error["message"]?.string, code: error["code"]?.string, payload: payload)
        default:
            break
        }
        return nil
    }

    /// Keeps a finished item for replay; unstored items can't be referenced by ID, so only reasoning keeps its ID.
    private mutating func record(_ item: JSONValue) {
        guard var fields = item.object else { return }
        if fields["type"]?.string == "function_call" {
            toolCalls.append(ToolCall(
                id: fields["call_id"]?.string ?? "",
                name: fields["name"]?.string ?? "",
                arguments: fields["arguments"]?.string ?? "{}"
            ))
        }
        if fields["type"]?.string != "reasoning" { fields["id"] = nil }
        fields["status"] = nil
        items.append(.object(fields))
    }

    /// The turn's text, tool calls, and output items for replay.
    func finishedTurn() throws -> AssistantTurn {
        AssistantTurn(text: text, toolCalls: toolCalls, nativeContent: .array(items))
    }
}
