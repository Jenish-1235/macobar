import Foundation
import Testing

/// Reads `stream` line by line the way `ModelClient` does, returning the reply text.
func replyText(from stream: String, format: some WireFormat) throws -> String {
    var reply = ""
    for line in stream.split(separator: "\n") {
        switch try format.read(line: String(line)) {
        case .text(let text): reply += text
        case .finished: return reply
        case .ignored: continue
        }
    }
    return reply
}

/// Parses a request body so it can be compared with an expected dictionary.
func jsonObject(_ data: Data) throws -> NSDictionary {
    try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
}

/// A user question and an earlier answer, shared by every body test.
let sampleConversation = [
    ChatMessage(role: .user, text: "Hi"),
    ChatMessage(role: .assistant, text: "Hello."),
    ChatMessage(role: .user, text: "What's on my calendar?"),
]

/// Verifies the Anthropic Messages request and its recorded stream.
struct AnthropicMessagesFormatTests {
    /// A recorded stream with thinking, a ping and two text deltas.
    static let recordedStream = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_01","type":"message","role":"assistant","content":[],"model":"claude-opus-5-5"}}
        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}
        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Keep it short."}}
        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"EqQB"}}
        event: content_block_stop
        data: {"type":"content_block_stop","index":0}
        event: content_block_start
        data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}
        event: ping
        data: {"type": "ping"}
        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello"}}
        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" there."}}
        event: content_block_stop
        data: {"type":"content_block_stop","index":1}
        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":12}}
        event: message_stop
        data: {"type":"message_stop"}
        """

    @Test("The Claude API default model asks for server-side fallbacks")
    func bodyWithFallbacks() throws {
        let format = ProviderAccount(kind: .claude, model: "claude-opus-5-5").wireFormat
        let body = try jsonObject(format.requestBody(model: "claude-opus-5-5", instructions: "Be brief.", conversation: sampleConversation))
        #expect(body == [
            "model": "claude-opus-5-5",
            "max_tokens": 64_000,
            "stream": true,
            "system": "Be brief.",
            "fallbacks": "default",
            "messages": [
                ["role": "user", "content": "Hi"],
                ["role": "assistant", "content": "Hello."],
                ["role": "user", "content": "What's on my calendar?"],
            ],
        ])
        #expect(format.formatHeaders == ["anthropic-version": "2023-06-01", "anthropic-beta": "server-side-fallback-2026-07-01"])
    }

    @Test("Bedrock and non-default models leave fallbacks out", arguments: [
        ProviderAccount(kind: .bedrock, model: "anthropic.claude-opus-5-5", setting: "us-east-1"),
        ProviderAccount(kind: .claude, model: "claude-haiku-5-5"),
    ])
    func bodyWithoutFallbacks(account: ProviderAccount) throws {
        let format = account.wireFormat
        let body = try jsonObject(format.requestBody(model: account.model, instructions: "", conversation: sampleConversation))
        #expect(body["fallbacks"] == nil)
        #expect(format.formatHeaders == ["anthropic-version": "2023-06-01"])
    }

    @Test("Only text deltas reach the reply; thinking and pings are skipped")
    func recordedReply() throws {
        #expect(try replyText(from: Self.recordedStream, format: AnthropicMessagesFormat(usesServerFallbacks: false)) == "Hello there.")
    }

    @Test("A refusal and a stream error both stop the reply")
    func failures() {
        let format = AnthropicMessagesFormat(usesServerFallbacks: false)
        #expect(throws: ModelClientError.declined) {
            try format.read(line: #"data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}"#)
        }
        #expect(throws: ModelClientError.failed("Overloaded")) {
            try format.read(line: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
        }
    }
}

/// Verifies the Chat Completions request and its recorded stream.
struct ChatCompletionsFormatTests {
    /// A recorded OpenRouter-style stream with a keep-alive comment, a role-only delta and `[DONE]`.
    static let recordedStream = """
        : OPENROUTER PROCESSING
        data: {"id":"gen-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}
        data: {"id":"gen-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Two"},"finish_reason":null}]}
        data: {"id":"gen-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":" meetings."},"finish_reason":null}]}
        data: {"id":"gen-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"total_tokens":20}}
        data: [DONE]
        data: {"choices":[{"delta":{"content":"after the end"}}]}
        """

    @Test("Instructions go first as a system message")
    func body() throws {
        let body = try jsonObject(ChatCompletionsFormat().requestBody(model: "gemini-3-pro", instructions: "Be brief.", conversation: sampleConversation))
        #expect(body == [
            "model": "gemini-3-pro",
            "stream": true,
            "messages": [
                ["role": "system", "content": "Be brief."],
                ["role": "user", "content": "Hi"],
                ["role": "assistant", "content": "Hello."],
                ["role": "user", "content": "What's on my calendar?"],
            ],
        ])
    }

    @Test("Content deltas form the reply, which ends at [DONE]")
    func recordedReply() throws {
        #expect(try replyText(from: Self.recordedStream, format: ChatCompletionsFormat()) == "Two meetings.")
    }

    @Test("An error chunk stops the reply")
    func failure() {
        #expect(throws: ModelClientError.failed("Provider returned error")) {
            try ChatCompletionsFormat().read(line: #"data: {"error":{"code":502,"message":"Provider returned error"}}"#)
        }
    }
}

/// Verifies the Responses request and its recorded stream.
struct ResponsesFormatTests {
    /// A recorded stream with lifecycle events around two text deltas.
    static let recordedStream = """
        event: response.created
        data: {"type":"response.created","sequence_number":0,"response":{"id":"resp_1","status":"in_progress"}}
        event: response.output_item.added
        data: {"type":"response.output_item.added","sequence_number":1,"output_index":0,"item":{"type":"message","role":"assistant","content":[]}}
        event: response.output_text.delta
        data: {"type":"response.output_text.delta","sequence_number":2,"item_id":"msg_1","output_index":0,"content_index":0,"delta":"Done"}
        event: response.output_text.delta
        data: {"type":"response.output_text.delta","sequence_number":3,"item_id":"msg_1","output_index":0,"content_index":0,"delta":" for today."}
        event: response.output_text.done
        data: {"type":"response.output_text.done","sequence_number":4,"text":"Done for today."}
        event: response.completed
        data: {"type":"response.completed","sequence_number":5,"response":{"id":"resp_1","status":"completed"}}
        """

    @Test("Requests are streamed and never stored")
    func body() throws {
        let body = try jsonObject(ResponsesFormat().requestBody(model: "gpt-5.5", instructions: "Be brief.", conversation: sampleConversation))
        #expect(body == [
            "model": "gpt-5.5",
            "stream": true,
            "store": false,
            "instructions": "Be brief.",
            "input": [
                ["role": "user", "content": "Hi"],
                ["role": "assistant", "content": "Hello."],
                ["role": "user", "content": "What's on my calendar?"],
            ],
        ])
    }

    @Test("Output text deltas form the reply")
    func recordedReply() throws {
        #expect(try replyText(from: Self.recordedStream, format: ResponsesFormat()) == "Done for today.")
    }

    @Test("Failed and cut-short responses stop the reply")
    func failures() {
        #expect(throws: ModelClientError.failed("Usage limit reached")) {
            try ResponsesFormat().read(line: #"data: {"type":"response.failed","response":{"error":{"code":"rate_limit","message":"Usage limit reached"}}}"#)
        }
        #expect(throws: ModelClientError.failed("Bad input")) {
            try ResponsesFormat().read(line: #"data: {"type":"error","code":"invalid","message":"Bad input"}"#)
        }
        #expect(throws: ModelClientError.failed("The reply was cut short (max_output_tokens).")) {
            try ResponsesFormat().read(line: #"data: {"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}"#)
        }
    }
}
