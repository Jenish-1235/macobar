import AppKit

/// Builds every module and connects them; the only place concrete types meet.
@MainActor
final class AppAssembly {
    /// Keeps the spacer gap in the Dock.
    private let gapReserver = DockGapReserver()
    /// Reports where the Dock and the gap are.
    private let dockObserver = DockObserver(reader: DockReader())
    /// Shows the field and reply sheet over the gap.
    private lazy var chatBar = ChatBarController(
        model: ChatBarModel(responder: PlaceholderResponder()),
        onQuit: { [weak self] in self?.quit() }
    )

    /// Waits for permission, reserves the Dock gap, then keeps the chat bar pinned to it.
    func start() async {
        await AccessibilityPermission.waitUntilGranted()
        gapReserver.reserveGap(width: ChatBarStyle.preferredFieldWidth)
        for await geometry in dockObserver.geometryUpdates() {
            chatBar.follow(geometry)
        }
    }

    /// Gives the Dock back its original layout and quits.
    private func quit() {
        gapReserver.releaseGap()
        NSApp.terminate(nil)
    }
}
