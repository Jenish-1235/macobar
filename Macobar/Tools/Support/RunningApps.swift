import AppKit

/// Finds running apps by the names people use for them.
enum RunningApps {
    /// Apps with a Dock presence, frontmost first.
    static var regular: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { $0.isActive && !$1.isActive }
    }

    /// The app the user is working in.
    static var frontmost: NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    /// The running app whose name matches `name` (exact, then prefix, case-insensitive), or the frontmost app when `name` is nil.
    static func find(_ name: String?) throws -> NSRunningApplication {
        guard let name else {
            guard let app = frontmost else { throw ToolError("No app is in front.") }
            return app
        }
        let apps = regular
        let match = apps.first { $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame }
            ?? apps.first { $0.localizedName?.lowercased().hasPrefix(name.lowercased()) == true }
        guard let match else { throw ToolError("\(name) isn't running. Running apps: \(apps.compactMap(\.localizedName).joined(separator: ", ")).") }
        return match
    }
}
