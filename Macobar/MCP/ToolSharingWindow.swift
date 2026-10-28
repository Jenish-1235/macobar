import AppKit
import SwiftUI

/// Hosts the Share Tools screen in its own charcoal window.
@MainActor
final class ToolSharingWindow {
    /// The charcoal window holding the screen.
    private let window: NSWindow

    /// Builds the window around `model`.
    init(model: ToolSharingModel) {
        window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Share Tools with AI Apps"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(SetupStyle.charcoal)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        let content = NSHostingView(rootView: ToolSharingView(model: model, onDone: { [weak self] in self?.window.close() }))
        window.contentView = content
        window.setContentSize(content.fittingSize)
    }

    /// Opens the window centred and in front.
    func show() {
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
