import AppKit

/// The system Dock process.
enum DockProcess {
    /// Bundle identifier of the Dock.
    static let bundleIdentifier = "com.apple.dock"

    /// The running Dock, or nil while it restarts.
    static var running: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    }

    /// Restarts the Dock so it reloads its preferences; macOS relaunches it automatically.
    static func restart() {
        guard let dock = running else { return }
        kill(dock.processIdentifier, SIGTERM)
    }
}
