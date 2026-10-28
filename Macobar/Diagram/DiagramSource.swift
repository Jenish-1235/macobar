/// Mermaid source as Macie sends it, cleaned and checked before it's drawn.
enum DiagramSource {
    /// Longest source accepted, in characters; past this a diagram is too slow and too dense to read.
    static let maximumLength = 20_000

    /// `text` without surrounding blank space or a Markdown code fence, or an error the model can fix when it's empty or too long.
    static func clean(_ text: String) throws -> String {
        var lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
        let source = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw ToolError("The diagram is empty; pass Mermaid source.") }
        guard source.count <= maximumLength else {
            throw ToolError("The diagram is \(source.count) characters; keep it under \(maximumLength).")
        }
        return source
    }
}
