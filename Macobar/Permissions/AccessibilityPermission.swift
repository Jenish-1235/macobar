import AppKit
import ApplicationServices

/// Checks and requests the Accessibility permission macobar needs to read the Dock.
enum AccessibilityPermission {
    /// Options key that makes the system show its "allow access" prompt.
    private static let promptOptionKey = "AXTrustedCheckOptionPrompt"
    /// Deep link to the Accessibility list in System Settings.
    private static let settingsLink = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    /// Whether the user has already granted Accessibility access.
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt, which also adds macobar to the list in System Settings.
    static func requestAccess() {
        _ = AXIsProcessTrustedWithOptions([promptOptionKey: true] as CFDictionary)
    }

    /// Opens System Settings at the Accessibility list.
    static func openSettings() {
        guard let url = URL(string: settingsLink) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Waits until access is granted, checking once a second.
    static func waitUntilGranted() async {
        while !isGranted {
            try? await Task.sleep(for: .seconds(1)) // Throws only on cancellation.
        }
    }
}
