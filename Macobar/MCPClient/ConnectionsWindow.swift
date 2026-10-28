import AppKit
import SwiftUI

/// Hosts the Connections screen in its own charcoal window.
@MainActor
final class ConnectionsWindow {
    /// The charcoal window holding the screen.
    private let window: NSWindow
    /// The servers and form shown.
    private let model: ConnectionsModel

    /// Builds the window around `model`.
    init(model: ConnectionsModel) {
        self.model = model
        window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Connections"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(SetupStyle.charcoal)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        let content = NSHostingView(rootView: ConnectionsView(model: model, onDone: { [weak self] in self?.window.close() }))
        window.contentView = content
        window.setContentSize(content.fittingSize)
    }

    /// Reloads the servers and opens the window centred and in front.
    func show() {
        Task { await model.refresh() }
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
