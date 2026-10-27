import CoreGraphics
import Observation

/// Tracks the two setup steps, Accessibility and the Dock gap, and performs them.
@MainActor
@Observable
final class SetupModel {
    /// Whether macobar has Accessibility access.
    private(set) var isAccessibilityGranted = AccessibilityPermission.isGranted
    /// Whether macobar asked for access and is waiting for the switch in System Settings.
    private(set) var isWaitingForAccessibility = false
    /// Whether the gap for the chat field is in the Dock.
    private(set) var isInDock: Bool
    /// Adds the gap to the Dock.
    @ObservationIgnored private let gapReserver: DockGapReserver
    /// Width the gap is sized for.
    @ObservationIgnored private let fieldWidth: CGFloat

    /// Creates the model, reading which steps are already done.
    init(gapReserver: DockGapReserver, fieldWidth: CGFloat) {
        self.gapReserver = gapReserver
        self.fieldWidth = fieldWidth
        self.isInDock = gapReserver.isGapReserved
    }

    /// Whether both steps are done.
    var isFinished: Bool { isAccessibilityGranted && isInDock }

    /// Asks for access the first time and reopens System Settings after that; returns true once access arrives.
    func allowAccessibility() async -> Bool {
        guard !isWaitingForAccessibility else {
            AccessibilityPermission.openSettings()
            return false
        }
        isWaitingForAccessibility = true
        AccessibilityPermission.requestAccess()
        await AccessibilityPermission.waitUntilGranted()
        isWaitingForAccessibility = false
        isAccessibilityGranted = true
        return true
    }

    /// Adds the chat field's gap to the Dock.
    func addToDock() {
        gapReserver.reserveGap(width: fieldWidth)
        isInDock = true
    }
}
