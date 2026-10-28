import Foundation

/// Something Macie can do on the Mac, described to the model and run when it asks.
protocol Tool: Sendable {
    /// Name the model calls it by, in snake_case.
    var name: String { get }
    /// When to use it and what it returns, written for the model.
    var description: String { get }
    /// JSON Schema of its arguments, built with `Schema`.
    var parameters: JSONValue { get }
    /// How much confirmation running it with `input` needs.
    func risk(for input: ToolInput) -> ToolRisk
    /// Whether running it with `input` brings outside text (a web page, file, screen, email, remote server, or names and labels others chose) into the conversation, after which risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool
    /// A short present-tense line for the reply card and approval prompt, e.g. "Opening Safari".
    func activity(for input: ToolInput) -> String
    /// Does the work and returns a short, plain-text result for the model.
    func run(_ input: ToolInput) async throws -> String
}

extension Tool {
    /// Reading and opening things needs no confirmation.
    func risk(for input: ToolInput) -> ToolRisk { .none }

    /// Most tools return only what they did, not outside text.
    func readsOutsideContent(for input: ToolInput) -> Bool { false }

    /// The tool as the model sees it.
    var definition: ToolDefinition {
        ToolDefinition(name: name, description: description, parameters: parameters)
    }
}

/// A tool whose result includes images for the model to look at; the agent calls `look` instead of `run`.
protocol VisualTool: Tool {
    /// Does the work and returns a short, plain-text result plus the images to show the model.
    func look(_ input: ToolInput) async throws -> (text: String, images: [ToolImage])
}

extension VisualTool {
    /// The text part of `look`, for callers that can't pass images on.
    func run(_ input: ToolInput) async throws -> String {
        try await look(input).text
    }
}

/// How much the user must confirm before a tool runs.
enum ToolRisk: Sendable {
    /// Runs without asking: reading and opening things.
    case none
    /// Asks, offering "Always allow" for this tool: changing things.
    case confirmOnce
    /// Asks every time: sending, deleting, scripts and shell commands.
    case confirmEveryTime
}

/// A tool failure explained in words the model can act on.
struct ToolError: LocalizedError {
    /// What went wrong.
    let message: String

    /// Creates an error with `message`.
    init(_ message: String) {
        self.message = message
    }

    /// The message, for `localizedDescription`.
    var errorDescription: String? { message }
}
