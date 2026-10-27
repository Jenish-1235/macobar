import AppKit
import SwiftUI

/// The setup window; closing it before setup is finished quits macobar.
@MainActor
final class SetupWindow: NSObject, NSWindowDelegate {
    /// The borderless-looking charcoal window.
    private let window: NSWindow
    /// Setup state, checked when the window closes.
    private let model: SetupModel

    /// Builds the window around `model`.
    init(model: SetupModel) {
        self.model = model
        window = NSWindow(
            contentRect: CGRect(origin: .zero, size: SetupStyle.windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "Set up macobar"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(SetupStyle.charcoal)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.delegate = self
        window.contentView = NSHostingView(rootView: SetupView(
            model: model,
            onFinish: { [weak self] in self?.window.close() }
        ))
    }

    /// Centres the window and brings macobar to the front.
    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Quits when setup is abandoned, since macobar can't work without it.
    func windowWillClose(_ notification: Notification) {
        guard !model.isFinished else { return }
        NSApp.terminate(nil)
    }
}
