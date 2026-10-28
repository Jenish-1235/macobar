import Foundation
import Testing

/// Verifies that images returned by tools reach the model in each wire format.
struct ToolImageTests {
    /// A tiny stand-in image whose base64 form is "AQID".
    static let image = ToolImage(data: Data([1, 2, 3]), mediaType: "image/jpeg")

    /// A screenshot call whose result carries one image.
    static let conversation: [ConversationItem] = [
        .user("What's on screen?"),
        .assistant(AssistantTurn(toolCalls: [ToolCall(id: "call_1", name: "take_screenshot", arguments: "{}")])),
        .toolResults([ToolResult(callID: "call_1", output: "Screenshot of the screen.", isError: false, images: [image])]),
    ]

    @Test("An image becomes a data URL")
    func dataURL() {
        #expect(Self.image.dataURL == "data:image/jpeg;base64,AQID")
    }

    @Test("Messages API tool results carry a text block and then base64 image blocks")
    func anthropicMessages() throws {
        let format = AnthropicMessagesFormat(isClaudeAPI: false, usesServerFallbacks: false)
        let body = try jsonBody(format.requestBody(model: "m", instructions: "", conversation: Self.conversation, tools: []))
        #expect(body["messages"]?.array?.last == ["role": "user", "content": [[
            "type": "tool_result",
            "tool_use_id": "call_1",
            "content": [
                ["type": "text", "text": "Screenshot of the screen."],
                ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": "AQID"]],
            ],
            "is_error": false,
        ]]])
    }

    @Test("Responses function output becomes input text followed by input images")
    func responses() throws {
        let body = try jsonBody(ResponsesFormat().requestBody(model: "m", instructions: "", conversation: Self.conversation, tools: []))
        #expect(body["input"]?.array?.last == [
            "type": "function_call_output",
            "call_id": "call_1",
            "output": [
                ["type": "input_text", "text": "Screenshot of the screen."],
                ["type": "input_image", "image_url": "data:image/jpeg;base64,AQID"],
            ],
        ])
    }

    @Test("Chat Completions keeps the tool message as text and adds one user message with the images")
    func chatCompletions() throws {
        let body = try jsonBody(ChatCompletionsFormat().requestBody(model: "m", instructions: "", conversation: Self.conversation, tools: []))
        let messages = body["messages"]?.array ?? []
        #expect(Array(messages.suffix(2)) == [
            ["role": "tool", "tool_call_id": "call_1", "content": "Screenshot of the screen."],
            ["role": "user", "content": [
                ["type": "text", "text": "Images from the tool results above."],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,AQID"]],
            ]],
        ])
    }

    @Test("Results without images add no user message")
    func chatCompletionsWithoutImages() throws {
        let body = try jsonBody(ChatCompletionsFormat().requestBody(model: "m", instructions: "", conversation: sampleConversation, tools: []))
        #expect(body["messages"]?.array?.last == ["role": "tool", "tool_call_id": "call_1", "content": "Opened Safari."])
    }
}
