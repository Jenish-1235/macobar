import AppKit
import SwiftUI

/// Shows Macie's drawings over every screen for a while, then fades them out.
@MainActor
final class ScreenOverlay {
    /// The drawing every screen's canvas shows.
    private let board = OverlayBoard()
    /// One panel per screen, made when something is first drawn.
    private var panels: [DrawingPanel] = []
    /// Fades the current drawing out when its time is up.
    private var fadeOut: Task<Void, Never>?

    /// Starts following screen changes, so panels always cover every screen.
    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildPanels() }
        }
    }

    /// Replaces whatever is drawn with `shapes` (AppKit global coordinates), fading them out after `duration`.
    func draw(_ shapes: [OverlayShape], duration: Duration) {
        fadeOut?.cancel()
        if panels.isEmpty { panels = NSScreen.screens.map(makePanel) }
        panels.forEach { $0.orderFrontRegardless() }
        withAnimation(OverlayStyle.fade) { board.drawing = OverlayDrawing(shapes: shapes) }
        fadeOut = Task { [weak self] in
            guard (try? await Task.sleep(for: duration)) != nil else { return }
            self?.clear()
        }
    }

    /// Fades out whatever is drawn, then hides the panels.
    func clear() {
        fadeOut?.cancel()
        withAnimation(OverlayStyle.fade) {
            board.drawing = nil
        } completion: { [weak self] in
            guard let self, board.drawing == nil else { return }
            panels.forEach { $0.orderOut(nil) }
        }
    }

    /// Replaces the panels after screens are added, removed or rearranged, keeping any drawing on show.
    private func rebuildPanels() {
        guard !panels.isEmpty else { return }
        panels.forEach { $0.close() }
        panels = NSScreen.screens.map(makePanel)
        if board.drawing != nil { panels.forEach { $0.orderFrontRegardless() } }
    }

    /// A panel covering `screen`, showing its share of the board.
    private func makePanel(for screen: NSScreen) -> DrawingPanel {
        let panel = DrawingPanel(screenFrame: screen.frame)
        let hostingView = NSHostingView(rootView: OverlayCanvas(board: board, screenFrame: screen.frame))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setFrame(screen.frame, display: false)
        return panel
    }
}
