import Foundation
import Testing

/// Reads `stream` line by line the way `ModelClient` does, returning the text shown and the finished turn.
func readReply(_ stream: String, format: some WireFormat) throws -> (text: String, turn: AssistantTurn) {
    var reader = format.makeReader()
    var text = ""
    for line in stream.split(separator: "\n") where line.hasPrefix("data:") {
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { break }
        text += try reader.read(payload: payload) ?? ""
        if reader.isFinished { break }
    }
    return (text, try reader.finishedTurn())
}

/// Parses a request body so it can be inspected.
func jsonBody(_ data: Data) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: data)
}

/// A tool every body test offers.
let sampleTool = ToolDefinition(name: "open_app", description: "Opens an app.", parameters: Schema.object(["name": Schema.string("App name")], required: ["name"]))

/// A conversation with a tool call and its result.
let sampleConversation: [ConversationItem] = [
    .user("Open Safari"),
    .assistant(AssistantTurn(text: "Opening it.", toolCalls: [ToolCall(id: "call_1", name: "open_app", arguments: #"{"name":"Safari"}"#)])),
    .toolResults([ToolResult(callID: "call_1", output: "Opened Safari.", isError: false)]),
]

/// Verifies the Anthropic Messages request and its recorded streams.
struct AnthropicMessagesFormatTests {
    /// A recorded stream with thinking, a ping and two text deltas.
    static let textStream = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_01","type":"message","role":"assistant","content":[],"model":"claude-opus-5-5"}}
        data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}
        data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Keep it short."}}
        data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"EqQB"}}
        data: {"type":"content_block_stop","index":0}
        data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}
        data: {"type": "ping"}
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello"}}
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" there."}}
        data: {"type":"content_block_stop","index":1}
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":12}}
        data: {"type":"message_stop"}
        """

    /// A recorded stream where Claude thinks, says a line, then calls a tool with streamed input.
    static let toolStream = """
        data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}
        data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig-1"}}
        data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Opening Safari."}}
        data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_1","name":"open_app","input":{}}}
        data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\\"name\\": \\"Saf"}}
        data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"ari\\"}"}}
        data: {"type":"content_block_stop","index":2}
        data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}
        data: {"type":"message_stop"}
        """

    @Test("The Claude API default model asks for fallbacks, caching and eager tool input")
    func claudeAPIBody() throws {
        let format = ProviderAccount(kind: .claude, model: "claude-opus-5-5").wireFormat
        let body = try jsonBody(format.requestBody(model: "claude-opus-5-5", instructions: "Be brief.", conversation: sampleConversation, tools: [sampleTool]))
        #expect(body["max_tokens"] == 64_000)
        #expect(body["system"] == "Be brief.")
        #expect(body["fallbacks"] == "default")
        #expect(body["cache_control"] == ["type": "ephemeral"])
        #expect(body["tools"] == [["name": "open_app", "description": "Opens an app.", "input_schema": sampleTool.parameters, "eager_input_streaming": true]])
        #expect(body["messages"] == [
            ["role": "user", "content": "Open Safari"],
            ["role": "assistant", "content": [
                ["type": "text", "text": "Opening it."],
                ["type": "tool_use", "id": "call_1", "name": "open_app", "input": ["name": "Safari"]],
            ]],
            ["role": "user", "content": [["type": "tool_result", "tool_use_id": "call_1", "content": "Opened Safari.", "is_error": false]]],
        ])
        #expect(format.formatHeaders == ["anthropic-version": "2023-06-01", "anthropic-beta": "server-side-fallback-2026-07-01"])
    }

    @Test("Bedrock leaves out Claude API-only fields")
    func bedrockBody() throws {
        let format = ProviderAccount(kind: .bedrock, model: "anthropic.claude-opus-5-5", setting: "us-east-1").wireFormat
        let body = try jsonBody(format.requestBody(model: "anthropic.claude-opus-5-5", instructions: "", conversation: sampleConversation, tools: [sampleTool]))
        #expect(body["fallbacks"] == nil)
        #expect(body["cache_control"] == nil)
        #expect(body["tools"]?.array?.first?["eager_input_streaming"] == nil)
        #expect(format.formatHeaders == ["anthropic-version": "2023-06-01"])
    }

    @Test("Only text deltas reach the reply; thinking and pings are skipped")
    func textReply() throws {
        let (text, turn) = try readReply(Self.textStream, format: AnthropicMessagesFormat(isClaudeAPI: true, usesServerFallbacks: false))
        #expect(text == "Hello there.")
        #expect(turn.text == "Hello there.")
        #expect(turn.toolCalls.isEmpty)
    }

    @Test("A tool call is assembled, and thinking is kept unchanged for replay")
    func toolReply() throws {
        let format = AnthropicMessagesFormat(isClaudeAPI: true, usesServerFallbacks: false)
        let (_, turn) = try readReply(Self.toolStream, format: format)
        #expect(turn.toolCalls == [ToolCall(id: "toolu_1", name: "open_app", arguments: #"{"name": "Safari"}"#)])
        #expect(turn.nativeContent == [
            ["type": "thinking", "thinking": "", "signature": "sig-1"],
            ["type": "text", "text": "Opening Safari."],
            ["type": "tool_use", "id": "toolu_1", "name": "open_app", "input": ["name": "Safari"]],
        ])
        let replayed = try jsonBody(format.requestBody(model: "m", instructions: "", conversation: [.user("Open Safari"), .assistant(turn)], tools: []))
        #expect(replayed["messages"]?.array?.last?["content"] == turn.nativeContent)
    }

    @Test("A refusal, a length cut-off and a stream error all stop the reply")
    func failures() {
        var reader = AnthropicReplyReader()
        #expect(throws: ModelClientError.declined) { try reader.read(payload: #"{"type":"message_delta","delta":{"stop_reason":"refusal"}}"#) }
        #expect(throws: replyCutShort) { try reader.read(payload: #"{"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#) }
        #expect(throws: ModelClientError.failed("Overloaded (overloaded_error)")) {
            try reader.read(payload: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
        }
    }
}

/// Verifies the Chat Completions request and its recorded streams.
struct ChatCompletionsFormatTests {
    /// A recorded OpenRouter-style stream with a keep-alive comment, a role-only delta and `[DONE]`.
    static let textStream = """
        : OPENROUTER PROCESSING
        data: {"id":"gen-1","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}
        data: {"id":"gen-1","choices":[{"index":0,"delta":{"content":"Two"},"finish_reason":null}]}
        data: {"id":"gen-1","choices":[{"index":0,"delta":{"content":" meetings."},"finish_reason":null}]}
        data: {"id":"gen-1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
        data: [DONE]
        data: {"choices":[{"delta":{"content":"after the end"}}]}
        """

    /// A recorded stream calling a tool in fragments, with a Gemini thought signature.
    static let toolStream = """
        data: {"choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_9","type":"function","function":{"name":"open_app","arguments":""},"extra_content":{"google":{"thought_signature":"ts-1"}}}]}}]}
        data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"name\\":"}}]}}]}
        data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"Notes\\"}"}}]}}]}
        data: {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}
        data: [DONE]
        """

    @Test("Instructions go first; tool calls and results use the chat shapes")
    func body() throws {
        let body = try jsonBody(ChatCompletionsFormat().requestBody(model: "gemini-3-pro", instructions: "Be brief.", conversation: sampleConversation, tools: [sampleTool]))
        #expect(body["messages"] == [
            ["role": "system", "content": "Be brief."],
            ["role": "user", "content": "Open Safari"],
            ["role": "assistant", "content": "Opening it.", "tool_calls": [
                ["id": "call_1", "type": "function", "function": ["name": "open_app", "arguments": #"{"name":"Safari"}"#]],
            ]],
            ["role": "tool", "tool_call_id": "call_1", "content": "Opened Safari."],
        ])
        #expect(body["tools"] == [["type": "function", "function": ["name": "open_app", "description": "Opens an app.", "parameters": sampleTool.parameters]]])
    }

    @Test("Content deltas form the reply, which ends at [DONE]")
    func textReply() throws {
        #expect(try readReply(Self.textStream, format: ChatCompletionsFormat()).text == "Two meetings.")
    }

    @Test("Tool-call fragments are joined and the thought signature is sent back")
    func toolReply() throws {
        let (_, turn) = try readReply(Self.toolStream, format: ChatCompletionsFormat())
        let signature: JSONValue = ["google": ["thought_signature": "ts-1"]]
        #expect(turn.toolCalls == [ToolCall(id: "call_9", name: "open_app", arguments: #"{"name":"Notes"}"#, providerExtra: signature)])
        let body = try jsonBody(ChatCompletionsFormat().requestBody(model: "m", instructions: "", conversation: [.assistant(turn)], tools: []))
        #expect(body["messages"]?.array?.last?["tool_calls"]?.array?.first?["extra_content"] == signature)
    }

    @Test("An error chunk or a length cut-off stops the reply")
    func failures() {
        var reader = ChatCompletionsReplyReader()
        #expect(throws: ModelClientError.failed("Provider returned error")) {
            try reader.read(payload: #"{"error":{"code":502,"message":"Provider returned error"}}"#)
        }
        #expect(throws: replyCutShort) { try reader.read(payload: #"{"choices":[{"delta":{},"finish_reason":"length"}]}"#) }
    }
}

/// Verifies the Responses request and its recorded streams.
struct ResponsesFormatTests {
    /// A recorded stream with lifecycle events around two text deltas.
    static let textStream = """
        data: {"type":"response.created","sequence_number":0,"response":{"id":"resp_1","status":"in_progress"}}
        data: {"type":"response.output_text.delta","sequence_number":2,"item_id":"msg_1","output_index":0,"content_index":0,"delta":"Done"}
        data: {"type":"response.output_text.delta","sequence_number":3,"item_id":"msg_1","output_index":0,"content_index":0,"delta":" for today."}
        data: {"type":"response.output_item.done","sequence_number":4,"output_index":0,"item":{"id":"msg_1","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Done for today.","annotations":[]}]}}
        data: {"type":"response.completed","sequence_number":5,"response":{"id":"resp_1","status":"completed"}}
        """

    /// A recorded stream with encrypted reasoning followed by a function call.
    static let toolStream = """
        data: {"type":"response.output_item.done","output_index":0,"item":{"id":"rs_1","type":"reasoning","summary":[],"encrypted_content":"enc-1"}}
        data: {"type":"response.function_call_arguments.delta","item_id":"fc_1","output_index":1,"delta":"{\\"name\\":\\"Music\\"}"}
        data: {"type":"response.output_item.done","output_index":1,"item":{"id":"fc_1","type":"function_call","status":"completed","call_id":"call_7","name":"open_app","arguments":"{\\"name\\":\\"Music\\"}"}}
        data: {"type":"response.completed","response":{"id":"resp_2","status":"completed"}}
        """

    @Test("Requests are streamed, unstored, ask for encrypted reasoning, and use function items")
    func body() throws {
        let body = try jsonBody(ResponsesFormat().requestBody(model: "gpt-6.1", instructions: "Be brief.", conversation: sampleConversation, tools: [sampleTool]))
        #expect(body["stream"] == true)
        #expect(body["store"] == false)
        #expect(body["include"] == ["reasoning.encrypted_content"])
        #expect(body["instructions"] == "Be brief.")
        #expect(body["input"] == [
            ["role": "user", "content": "Open Safari"],
            ["role": "assistant", "content": "Opening it."],
            ["type": "function_call", "call_id": "call_1", "name": "open_app", "arguments": #"{"name":"Safari"}"#],
            ["type": "function_call_output", "call_id": "call_1", "output": "Opened Safari."],
        ])
        #expect(body["tools"] == [["type": "function", "name": "open_app", "description": "Opens an app.", "parameters": sampleTool.parameters]])
    }

    @Test("Output text deltas form the reply")
    func textReply() throws {
        #expect(try readReply(Self.textStream, format: ResponsesFormat()).text == "Done for today.")
    }

    @Test("Function calls are read, and items are replayed without stored IDs except reasoning")
    func toolReply() throws {
        let (_, turn) = try readReply(Self.toolStream, format: ResponsesFormat())
        #expect(turn.toolCalls == [ToolCall(id: "call_7", name: "open_app", arguments: #"{"name":"Music"}"#)])
        #expect(turn.nativeContent == [
            ["id": "rs_1", "type": "reasoning", "summary": [], "encrypted_content": "enc-1"],
            ["type": "function_call", "call_id": "call_7", "name": "open_app", "arguments": #"{"name":"Music"}"#],
        ])
    }

    @Test("Failed and cut-short responses stop the reply")
    func failures() {
        var reader = ResponsesReplyReader()
        #expect(throws: ModelClientError.failed("The server had an error (server_error)")) {
            try reader.read(payload: #"{"type":"response.failed","response":{"error":{"code":"server_error","message":"The server had an error"}}}"#)
        }
        #expect(throws: ModelClientError.failed("Bad input (invalid)")) { try reader.read(payload: #"{"type":"error","code":"invalid","message":"Bad input"}"#) }
        #expect(throws: ModelClientError.failed("Tools are not supported (unsupported_parameter)")) {
            try reader.read(payload: #"{"type":"error","error":{"type":"invalid_request_error","code":"unsupported_parameter","message":"Tools are not supported"}}"#)
        }
        #expect(throws: ModelClientError.failed(#"The provider reported an error: {"type":"error","sequence_number":3}"#)) {
            try reader.read(payload: #"{"type":"error","sequence_number":3}"#)
        }
        #expect(throws: replyCutShort) {
            try reader.read(payload: #"{"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}"#)
        }
    }
}
