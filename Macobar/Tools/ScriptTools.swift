import Foundation

/// Runs an AppleScript the model writes.
struct RunAppleScriptTool: Tool {
    /// Name the model calls it by.
    let name = "run_applescript"
    /// When to use it and what it returns.
    let description = "Runs an AppleScript; a last resort for scriptable apps when no specific tool fits. The user approves every run."

    /// The script source.
    var parameters: JSONValue {
        Schema.object(["script": Schema.string("AppleScript source.")], required: ["script"])
    }

    /// Arbitrary scripts ask every time.
    func risk(for input: ToolInput) -> ToolRisk {
        .confirmEveryTime
    }

    /// Its result carries outside text the model will read, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Describes the run.
    func activity(for input: ToolInput) -> String {
        "Running an AppleScript"
    }

    /// Runs the script for up to a minute.
    func run(_ input: ToolInput) async throws -> String {
        let output = try await AppleScript.run(input.requiredString("script"), timeout: 60)
        return output.isEmpty ? "Done (no output)." : output
    }
}

/// Runs a shell command in the user's login shell.
struct RunShellTool: Tool {
    /// Most output characters returned to the model.
    private let outputLimit = 20_000

    /// Name the model calls it by.
    let name = "run_shell"
    /// When to use it and what it returns.
    let description = """
        Runs a command in the user's login zsh from their home folder, for file, developer and system tasks no specific \
        tool covers. The user approves every run. Returns stdout and stderr, plus the exit status on failure.
        """

    /// The command and how long it may run.
    var parameters: JSONValue {
        Schema.object([
            "command": Schema.string("zsh command."),
            "timeout_seconds": Schema.integer("Seconds, 1-300; default 60."),
        ], required: ["command"])
    }

    /// Shell commands ask every time.
    func risk(for input: ToolInput) -> ToolRisk {
        .confirmEveryTime
    }

    /// Its result carries outside text the model will read, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Shows the command, shortened to one line.
    func activity(for input: ToolInput) -> String {
        let command = (input.string("command") ?? "").split(whereSeparator: \.isNewline).joined(separator: "; ")
        return "Running `\(command.count > 80 ? command.prefix(79) + "…" : command)`"
    }

    /// Runs the command from the home folder, reporting a non-zero exit status after its output.
    func run(_ input: ToolInput) async throws -> String {
        let timeout = min(max(input.integer("timeout_seconds") ?? 60, 1), 300)
        // The command arrives as $1 so the wrapper can report its exit status without splicing it into the source.
        let wrapper = #"cd ~ || exit; eval "$1"; exit_status=$?; (( exit_status )) && print -r -- "[exit status $exit_status]"; exit $exit_status"#
        do {
            let output = try await ProcessRunner.run("/bin/zsh", ["-lc", wrapper, "zsh", input.requiredString("command")], timeout: TimeInterval(timeout))
            return output.isEmpty ? "Done (no output)." : truncated(output)
        } catch let error as ToolError {
            throw ToolError(truncated(error.message))
        }
    }

    /// The last `outputLimit` characters of `output`, noting how much was cut.
    private func truncated(_ output: String) -> String {
        guard output.count > outputLimit else { return output }
        return "[first \(output.count - outputLimit) characters truncated]\n" + output.suffix(outputLimit)
    }
}
