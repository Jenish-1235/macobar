import Foundation

/// Remembers which tools the user chose to always allow.
struct ToolApprovals: Sendable {
    /// Preferences key holding the always-allowed tool names.
    private static let key = "alwaysAllowedTools"

    /// Whether the user always allows `toolName`.
    func isAlwaysAllowed(_ toolName: String) -> Bool {
        UserDefaults.standard.stringArray(forKey: Self.key)?.contains(toolName) == true
    }

    /// Forgets every Always Allow for tools whose names start with `prefix`, e.g. a removed MCP server's "name__" tools.
    func revoke(namesStartingWith prefix: String) {
        let names = (UserDefaults.standard.stringArray(forKey: Self.key) ?? []).filter { !$0.hasPrefix(prefix) }
        UserDefaults.standard.set(names, forKey: Self.key)
    }

    /// Stops asking before `toolName` runs.
    func alwaysAllow(_ toolName: String) {
        let names = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? []).union([toolName])
        UserDefaults.standard.set(names.sorted(), forKey: Self.key)
    }
}
