import ApplicationServices

/// Checks and requests the Accessibility permission macobar needs to read the Dock.
enum AccessibilityPermission {
    /// Options key that makes the system show its "allow access" prompt.
    private static let promptOptionKey = "AXTrustedCheckOptionPrompt"

    /// Whether the user has already granted Accessibility access.
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt if needed, then waits until access is granted.
    static func waitUntilGranted() async {
        let options = [promptOptionKey: true] as CFDictionary
        guard !AXIsProcessTrustedWithOptions(options) else { return }
        while !isGranted {
            try? await Task.sleep(for: .seconds(1)) // Throws only on cancellation.
        }
    }
}
