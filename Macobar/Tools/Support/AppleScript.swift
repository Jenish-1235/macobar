/// Runs AppleScript through `osascript`, passing values as arguments so they can't break out of the script.
enum AppleScript {
    /// Runs `source`, whose `on run argv` handler receives `arguments`; returns what the script returns.
    static func run(_ source: String, arguments: [String] = [], timeout: Double = 30) async throws -> String {
        try await ProcessRunner.run("/usr/bin/osascript", ["-e", source] + arguments, timeout: timeout)
    }
}
