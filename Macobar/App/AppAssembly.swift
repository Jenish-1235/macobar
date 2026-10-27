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
    /// The setup window, kept alive while it's open.
    private var setupWindow: SetupWindow?

    /// Shows setup if anything is missing, then keeps the chat bar pinned to the Dock gap.
    func start() async {
        let setup = SetupModel(gapReserver: gapReserver, fieldWidth: ChatBarStyle.preferredFieldWidth)
        if !setup.isFinished {
            setupWindow = SetupWindow(model: setup)
            setupWindow?.show()
        }
        await AccessibilityPermission.waitUntilGranted()
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
