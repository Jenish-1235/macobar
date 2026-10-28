import Foundation

/// Lists the user's Shortcuts.
struct ListShortcutsTool: Tool {
    let name = "list_shortcuts"
    let description = "Lists the user's Shortcuts by name. Call it before run_shortcut if unsure of the exact name."
    var parameters: JSONValue { Schema.object() }

    func activity(for input: ToolInput) -> String {
        "Listing shortcuts"
    }

    func run(_ input: ToolInput) async throws -> String {
        let names = try await ProcessRunner.run("/usr/bin/shortcuts", ["list"])
        return names.isEmpty ? "The user has no shortcuts." : names
    }
}

/// Runs one of the user's Shortcuts.
struct RunShortcutTool: Tool {
    let name = "run_shortcut"
    let description = """
        Runs one of the user's Shortcuts by exact name, for a shortcut they ask for or one that does what they want \
        (see list_shortcuts). Returns its text output.
        """
    var parameters: JSONValue {
        Schema.object([
            "name": Schema.string("Exact shortcut name."),
            "input": Schema.string("Text input."),
        ], required: ["name"])
    }

    func risk(for input: ToolInput) -> ToolRisk { .confirmOnce }

    /// Its result is whatever the shortcut returned, which can include web pages or files.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    func activity(for input: ToolInput) -> String {
        "Running the “\(input.string("name") ?? "")” shortcut"
    }

    func run(_ input: ToolInput) async throws -> String {
        let shortcutName = try input.requiredString("name")
        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: folder) }
        let outputURL = folder.appendingPathComponent("output")
        var arguments = ["run", "--output-path", outputURL.path]
        if let text = input.rawString("input") {
            let inputURL = folder.appendingPathComponent("input.txt")
            try text.write(to: inputURL, atomically: true, encoding: .utf8)
            arguments += ["--input-path", inputURL.path]
        }
        arguments += ["--", shortcutName]
        _ = try await ProcessRunner.run("/usr/bin/shortcuts", arguments, timeout: 120)
        guard let output = try? String(contentsOf: outputURL, encoding: .utf8),
              !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Ran \(shortcutName)."
        }
        return output
    }
}
