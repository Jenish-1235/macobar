import Foundation

/// One entry in a conversation with a model.
enum ConversationItem: Equatable, Sendable {
    /// Something the user typed.
    case user(String)
    /// One model reply: text, tool calls, or both.
    case assistant(AssistantTurn)
    /// What the requested tools returned, in call order.
    case toolResults([ToolResult])
}

/// One complete model reply.
struct AssistantTurn: Equatable, Sendable {
    /// The reply's text.
    var text = ""
    /// Tools the model asked to run.
    var toolCalls: [ToolCall] = []
    /// The reply in the provider's own shape, replayed unchanged next time (Claude's thinking blocks, OpenAI's reasoning items).
    var nativeContent: JSONValue?
}

/// A model's request to run one tool.
struct ToolCall: Equatable, Sendable {
    /// The provider's ID for this call, echoed in the result.
    let id: String
    /// Name of the tool.
    let name: String
    /// The tool's arguments as a JSON object string.
    let arguments: String
    /// Provider-specific data that must travel with the call (Gemini's thought signature).
    var providerExtra: JSONValue?
}

/// What one tool call returned.
struct ToolResult: Equatable, Sendable {
    /// The call this answers.
    let callID: String
    /// The tool's output, or what went wrong.
    let output: String
    /// Whether the tool failed or was declined.
    let isError: Bool
    /// Images the tool returned for the model to look at, such as a screenshot.
    var images: [ToolImage] = []
}

/// An image a tool hands back to the model.
struct ToolImage: Equatable, Sendable {
    /// The encoded image bytes.
    let data: Data
    /// The bytes' MIME type, e.g. "image/jpeg".
    let mediaType: String

    /// The image as a `data:` URL, the form OpenAI's APIs take.
    var dataURL: String {
        "data:\(mediaType);base64,\(data.base64EncodedString())"
    }
}

/// A tool as the model sees it.
struct ToolDefinition: Equatable, Sendable {
    /// Name the model calls it by.
    let name: String
    /// When and why to use it.
    let description: String
    /// JSON Schema of its arguments.
    let parameters: JSONValue
}
