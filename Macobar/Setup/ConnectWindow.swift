import AppKit
import SwiftUI

/// Hosts the Connect screen, as a sheet over setup or as its own window from the Dock.
@MainActor
final class ConnectWindow {
    /// The charcoal window holding the screen.
    private let window: NSWindow
    /// The window this one is a sheet on, if any.
    private weak var parent: NSWindow?

    /// Builds the window around `model`.
    init(model: ConnectModel) {
        window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Connect a model"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(SetupStyle.charcoal)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        let content = NSHostingView(rootView: ConnectView(model: model, onCancel: { [weak self] in self?.close() }))
        window.contentView = content
        window.setContentSize(content.fittingSize)
    }

    /// Slides down over `parent`, or opens centred and in front when there is none.
    func show(over parent: NSWindow?) {
        self.parent = parent
        NSApp.activate()
        if let parent {
            parent.beginSheet(window)
        } else {
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Dismisses the sheet or closes the window.
    func close() {
        if let parent {
            parent.endSheet(window)
        } else {
            window.close()
        }
    }
}
