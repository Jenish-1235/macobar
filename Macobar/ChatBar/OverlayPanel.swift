import AppKit

/// A borderless, transparent panel that floats just above the Dock on every Space without activating macobar.
final class OverlayPanel: NSPanel {
    /// Whether this panel may take keyboard focus; only the text field's panel does.
    private let acceptsKeyFocus: Bool

    /// Creates an empty, hidden panel.
    init(acceptsKeyFocus: Bool) {
        self.acceptsKeyFocus = acceptsKeyFocus
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    /// Lets the field's panel receive typing.
    override var canBecomeKey: Bool { acceptsKeyFocus }

    /// Never becomes main, so the user's app keeps its main window.
    override var canBecomeMain: Bool { false }

    /// Gives keyboard focus back to the app that was in front before the user clicked in.
    func handBackKeyFocus() {
        orderOut(nil)
        orderFrontRegardless()
    }
}
