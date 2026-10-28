import Foundation

/// Anthropic's Messages API, spoken by Claude and Claude on Amazon Bedrock.
struct AnthropicMessagesFormat: WireFormat {
    /// Whether requests go to the Claude API itself, which has features Bedrock lacks.
    let isClaudeAPI: Bool
    /// Whether declined requests are retried server-side on another model (Claude API, default model only).
    let usesServerFallbacks: Bool

    /// The API version, plus the fallback beta when it's used.
    var formatHeaders: [String: String] {
        var headers = ["anthropic-version": "2023-06-01"]
        if usesServerFallbacks { headers["anthropic-beta"] = "server-side-fallback-2026-07-01" }
        return headers
    }

    /// A streamed Messages request. Thinking is left at the model's default (adaptive on current models).
    func requestBody(model: String, instructions: String, conversation: [ConversationItem], tools: [ToolDefinition]) throws -> Data {
        var body: [String: JSONValue] = [
            "model": .string(model),
            "max_tokens": 64_000,
            "stream": true,
            "system": .string(instructions),
            "messages": .array(conversation.map(message)),
        ]
        if !tools.isEmpty { body["tools"] = .array(tools.map(toolSchema)) }
        if isClaudeAPI { body["cache_control"] = ["type": "ephemeral"] }
        if usesServerFallbacks { body["fallbacks"] = "default" }
        return try JSONValue.object(body).encoded()
    }

    /// A reader for Messages stream events.
    func makeReader() -> any ReplyReader {
        AnthropicReplyReader()
    }

    /// One conversation item as a Messages API message.
    private func message(_ item: ConversationItem) -> JSONValue {
        switch item {
        case .user(let text):
            return ["role": "user", "content": .string(text)]
        case .assistant(let turn):
            return ["role": "assistant", "content": turn.nativeContent ?? Self.content(of: turn)]
        case .toolResults(let results):
            return ["role": "user", "content": .array(results.map(Self.toolResult))]
        }
    }

    /// A tool result block; when the tool returned images, its content is a text block followed by image blocks.
    private static func toolResult(_ result: ToolResult) -> JSONValue {
        let images: [JSONValue] = result.images.map { image in
            ["type": "image", "source": ["type": "base64", "media_type": .string(image.mediaType), "data": .string(image.data.base64EncodedString())]]
        }
        let content: JSONValue = images.isEmpty ? .string(result.output) : .array([["type": "text", "text": .string(result.output)]] + images)
        return ["type": "tool_result", "tool_use_id": .string(result.callID), "content": content, "is_error": .bool(result.isError)]
    }

    /// Content blocks for a turn that has no native form.
    private static func content(of turn: AssistantTurn) -> JSONValue {
        let text: [JSONValue] = turn.text.isEmpty ? [] : [["type": "text", "text": .string(turn.text)]]
        let calls: [JSONValue] = turn.toolCalls.map { call in
            ["type": "tool_use", "id": .string(call.id), "name": .string(call.name), "input": .arguments(call.arguments)]
        }
        return .array(text + calls)
    }

    /// A tool in Messages API form; on the Claude API, inputs stream as they're written.
    private func toolSchema(_ tool: ToolDefinition) -> JSONValue {
        var schema: [String: JSONValue] = ["name": .string(tool.name), "description": .string(tool.description), "input_schema": tool.parameters]
        if isClaudeAPI { schema["eager_input_streaming"] = true }
        return .object(schema)
    }
}

/// Rebuilds a Messages reply's content blocks (text, thinking, tool use) from stream events.
struct AnthropicReplyReader: ReplyReader {
    /// Blocks by index, as started and then extended by deltas.
    private var blocks: [Int: [String: JSONValue]] = [:]
    /// Tool input JSON received so far, by block index.
    private var partialInputs: [Int: String] = [:]
    /// Whether `message_stop` arrived.
    private(set) var isFinished = false

    /// Applies one stream event, returning new reply text.
    mutating func read(payload: String) throws -> String? {
        let event = try JSONValue.parse(payload)
        let index = event["index"]?.number.flatMap { Int(exactly: $0.rounded(.towardZero)) } ?? 0
        switch event["type"]?.string {
        case "content_block_start":
            blocks[index] = event["content_block"]?.object ?? [:]
        case "content_block_delta":
            return apply(event["delta"] ?? [:], toBlock: index)
        case "message_delta":
            switch event["delta"]?["stop_reason"]?.string {
            case "refusal": throw ModelClientError.declined
            case "max_tokens": throw replyCutShort
            default: break
            }
        case "message_stop":
            isFinished = true
        case "error":
            throw ModelClientError.streamError(message: event["error"]?["message"]?.string, code: event["error"]?["type"]?.string, payload: payload)
        default:
            break
        }
        return nil
    }

    /// Extends block `index` with `delta`, returning text that should appear in the reply.
    private mutating func apply(_ delta: JSONValue, toBlock index: Int) -> String? {
        switch delta["type"]?.string {
        case "text_delta":
            let text = delta["text"]?.string ?? ""
            append(text, to: "text", ofBlock: index)
            return text
        case "thinking_delta":
            append(delta["thinking"]?.string ?? "", to: "thinking", ofBlock: index)
        case "signature_delta":
            blocks[index, default: [:]]["signature"] = delta["signature"]
        case "input_json_delta":
            partialInputs[index, default: ""] += delta["partial_json"]?.string ?? ""
        default:
            break
        }
        return nil
    }

    /// Appends `text` to the string field `field` of block `index`.
    private mutating func append(_ text: String, to field: String, ofBlock index: Int) {
        blocks[index, default: [:]][field] = .string((blocks[index]?[field]?.string ?? "") + text)
    }

    /// The turn: its text, its tool calls, and every block in order for replay.
    func finishedTurn() throws -> AssistantTurn {
        var turn = AssistantTurn()
        var content: [JSONValue] = []
        for index in blocks.keys.sorted() {
            guard var block = blocks[index] else { continue }
            switch block["type"]?.string {
            case "text":
                turn.text += block["text"]?.string ?? ""
            case "tool_use":
                let arguments = partialInputs[index] ?? block["input"]?.jsonString ?? "{}"
                block["input"] = .arguments(arguments.isEmpty ? "{}" : arguments)
                turn.toolCalls.append(ToolCall(id: block["id"]?.string ?? "", name: block["name"]?.string ?? "", arguments: arguments))
            case "thinking", "redacted_thinking":
                break
            default:
                continue
            }
            content.append(.object(block))
        }
        turn.nativeContent = .array(content)
        return turn
    }
}
