import AppKit
import SwiftUI

/// Hosts the History screen in its own charcoal window.
@MainActor
final class HistoryWindow {
    /// The charcoal window holding the screen.
    private let window: NSWindow
    /// The entries shown, read again each time the window opens.
    private let model: HistoryModel

    /// Builds the window around `model`.
    init(model: HistoryModel) {
        self.model = model
        window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "History"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(SetupStyle.charcoal)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        let content = NSHostingView(rootView: HistoryView(model: model, onDone: { [weak self] in self?.window.close() }))
        window.contentView = content
        window.setContentSize(content.fittingSize)
    }

    /// Reads the log again and opens the window centred and in front.
    func show() {
        model.reload()
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
