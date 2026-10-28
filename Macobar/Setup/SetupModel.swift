import CoreGraphics
import Observation

/// Tracks the three setup steps (Accessibility, the Dock gap, a model) and performs the first two.
@MainActor
@Observable
final class SetupModel {
    /// Whether macobar has Accessibility access.
    private(set) var isAccessibilityGranted = AccessibilityPermission.isGranted
    /// Whether macobar asked for access and is waiting for the switch in System Settings.
    private(set) var isWaitingForAccessibility = false
    /// Whether the gap for the chat field is in the Dock.
    private(set) var isInDock: Bool
    /// The provider Macie is connected to, or nil before one is connected.
    private(set) var connectedProvider: ProviderKind?
    /// Adds the gap to the Dock.
    @ObservationIgnored private let gapReserver: DockGapReserver
    /// Width the gap is sized for.
    @ObservationIgnored private let fieldWidth: CGFloat

    /// Creates the model, reading which steps are already done.
    init(gapReserver: DockGapReserver, fieldWidth: CGFloat, connectedProvider: ProviderKind?) {
        self.gapReserver = gapReserver
        self.fieldWidth = fieldWidth
        self.isInDock = gapReserver.isGapReserved
        self.connectedProvider = connectedProvider
    }

    /// Whether every step is done.
    var isFinished: Bool { isAccessibilityGranted && isInDock && connectedProvider != nil }

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

    /// Records that `provider` was checked and saved on the Connect screen.
    func modelDidConnect(_ provider: ProviderKind) {
        connectedProvider = provider
    }
}
