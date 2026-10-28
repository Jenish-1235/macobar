import AppKit

/// Reads or replaces the text on the clipboard.
struct ClipboardTool: Tool {
    /// What to do with the clipboard.
    private enum Action: String, CaseIterable {
        /// Return the clipboard's text.
        case read
        /// Put `text` on the clipboard.
        case write
    }

    /// Most characters returned when reading.
    private static let characterLimit = 30_000

    let name = "clipboard"
    let description = """
        Reads or writes the clipboard text. Read when the user means "what I copied"; write when they want something \
        copied to paste.
        """
    var parameters: JSONValue {
        Schema.object([
            "action": Schema.oneOf(Action.allCases.map(\.rawValue), "Read or write."),
            "text": Schema.string("For write: the text."),
        ], required: ["action"])
    }

    func risk(for input: ToolInput) -> ToolRisk {
        Action(rawValue: input.string("action") ?? "") == .read ? .none : .confirmOnce
    }

    /// Reading brings outside text the model will read, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        input.string("action") == "read"
    }

    func activity(for input: ToolInput) -> String {
        Action(rawValue: input.string("action") ?? "") == .read ? "Reading the clipboard" : "Copying text to the clipboard"
    }

    func run(_ input: ToolInput) async throws -> String {
        switch Action(rawValue: try input.requiredString("action")) {
        case .read:
            guard let text = await MainActor.run(body: { NSPasteboard.general.string(forType: .string) }), !text.isEmpty else {
                return "The clipboard has no text."
            }
            guard text.count > Self.characterLimit else { return text }
            return "\(text.prefix(Self.characterLimit))\n[Truncated: showing the first \(Self.characterLimit) of \(text.count) characters.]"
        case .write:
            guard let text = input.rawString("text") else { throw ToolError("Missing required argument \"text\".") }
            let didWrite = await MainActor.run {
                NSPasteboard.general.clearContents()
                return NSPasteboard.general.setString(text, forType: .string)
            }
            guard didWrite else { throw ToolError("Couldn't write to the clipboard.") }
            return "Copied to the clipboard."
        case nil:
            throw ToolError("Unknown action. Use read or write.")
        }
    }
}
