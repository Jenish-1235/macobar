import AppKit

/// A transparent, click-through panel covering one screen, on every Space and over full-screen apps.
final class DrawingPanel: NSPanel {
    /// Creates a hidden panel covering `screenFrame`.
    init(screenFrame: CGRect) {
        super.init(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow))) // Over apps and the Dock, under the chat field and reply card.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    /// Never takes keyboard focus.
    override var canBecomeKey: Bool { false }

    /// Never becomes main, so the user's app keeps its main window.
    override var canBecomeMain: Bool { false }
}
