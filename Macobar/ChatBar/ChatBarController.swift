import AppKit
import SwiftUI

/// Places the chat field inside the Dock gap and the reply sheet just above it.
@MainActor
final class ChatBarController {
    /// Panel holding the text field, sized to the gap.
    private let fieldPanel = OverlayPanel(acceptsKeyFocus: true)
    /// Panel holding the reply sheet, sized to its content.
    private let replyPanel = OverlayPanel(acceptsKeyFocus: false)
    /// Shared chat state.
    private let model: ChatBarModel
    /// Latest Dock geometry, or nil while the gap isn't visible.
    private var geometry: DockGeometry?
    /// Latest natural size of the reply sheet; zero when collapsed.
    private var replySize = CGSize.zero

    /// Builds both panels around `model`; the callbacks run when the user picks Change Model or Quit.
    init(model: ChatBarModel, onChangeModel: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.model = model
        fieldPanel.contentView = hostingView(for: ChatFieldView(
            model: model,
            onLeave: { [weak fieldPanel] in fieldPanel?.handBackKeyFocus() },
            onChangeModel: onChangeModel,
            onQuit: onQuit
        ))
        replyPanel.contentView = hostingView(for: ReplySheetView(
            model: model,
            onSizeChange: { [weak self] size in self?.resizeReply(to: size) }
        ))
        collapseFinishedReplyWhenUserClicksAway()
    }

    /// Moves both panels to match the Dock, hiding them while the gap isn't on screen.
    func follow(_ geometry: DockGeometry?) {
        self.geometry = geometry
        guard let geometry else {
            fieldPanel.orderOut(nil)
            replyPanel.orderOut(nil)
            return
        }
        fieldPanel.setFrame(fieldFrame(in: geometry), display: true)
        fieldPanel.orderFrontRegardless()
        placeReplyPanel()
    }

    /// The field capsule's frame: the gap, trimmed to icon height and centred.
    private func fieldFrame(in geometry: DockGeometry) -> CGRect {
        let gap = geometry.gapFrame
        let height = min(gap.height - 2 * ChatBarStyle.fieldVerticalMargin, ChatBarStyle.maxFieldHeight)
        return gap.insetBy(dx: ChatBarStyle.fieldHorizontalMargin, dy: (gap.height - height) / 2)
    }

    /// Records the sheet's new size and re-places its panel.
    private func resizeReply(to size: CGSize) {
        replySize = size
        placeReplyPanel()
    }

    /// Pins the reply panel above the Dock, centred on the field and kept on screen; hides it when empty.
    private func placeReplyPanel() {
        guard let geometry, replySize.width > 0, replySize.height > 0 else {
            replyPanel.orderOut(nil)
            return
        }
        var frame = CGRect(
            x: geometry.gapFrame.midX - replySize.width / 2,
            y: geometry.dockFrame.maxY + ChatBarStyle.replyLift,
            width: replySize.width,
            height: replySize.height
        )
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(geometry.gapFrame) }) {
            frame.origin.x = min(max(frame.minX, screen.frame.minX), screen.frame.maxX - frame.width)
        }
        replyPanel.setFrame(frame, display: true)
        replyPanel.orderFrontRegardless()
    }

    /// Collapses a finished reply when the field loses focus, like Spotlight does.
    private func collapseFinishedReplyWhenUserClicksAway() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: fieldPanel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.dismissIfFinished() }
        }
    }

    /// Wraps a SwiftUI view so the panel, not SwiftUI, decides the window size.
    private func hostingView(for view: some View) -> NSView {
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = []
        return hostingView
    }
}
