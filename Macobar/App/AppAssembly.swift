import AppKit

/// Builds every module and connects them; the only place concrete types meet.
@MainActor
final class AppAssembly {
    /// Keeps the spacer gap in the Dock.
    private let gapReserver = DockGapReserver()
    /// Reports where the Dock and the gap are.
    private let dockObserver = DockObserver(reader: DockReader())
    /// The saved provider and its key.
    private let accountStore = ProviderAccountStore()
    /// Shows the field and reply sheet over the gap; replies come from whichever model is active.
    private lazy var chatBar = ChatBarController(
        model: ChatBarModel(responder: ModelResponder(accountStore: accountStore)),
        onChangeModel: { [weak self] in self?.showConnect(over: nil) },
        onQuit: { NSApp.terminate(nil) }
    )
    /// Setup state, kept to mark step 3 done.
    private var setup: SetupModel?
    /// The setup window, kept alive while it's open.
    private var setupWindow: SetupWindow?
    /// The Connect screen, kept alive while it's open.
    private var connectWindow: ConnectWindow?

    /// Restores the gap if the user added macobar before, shows setup if anything is missing, then keeps the chat bar pinned to the gap.
    func start() async {
        if gapReserver.wasAddedByUser {
            gapReserver.reserveGap(width: ChatBarStyle.preferredFieldWidth)
        }
        let setup = SetupModel(
            gapReserver: gapReserver,
            fieldWidth: ChatBarStyle.preferredFieldWidth,
            connectedProvider: accountStore.activeAccount?.kind
        )
        self.setup = setup
        if !setup.isFinished {
            setupWindow = SetupWindow(model: setup, onConnectModel: { [weak self] in self?.showConnect(over: $0) })
            setupWindow?.show()
        }
        await AccessibilityPermission.waitUntilGranted()
        for await geometry in dockObserver.geometryUpdates() {
            chatBar.follow(geometry)
        }
    }

    /// Opens the Connect screen, as a sheet over `parent` or on its own.
    private func showConnect(over parent: NSWindow?) {
        connectWindow?.close()
        let model = ConnectModel(store: accountStore, onConnected: { [weak self] in self?.modelDidConnect() })
        connectWindow = ConnectWindow(model: model)
        connectWindow?.show(over: parent)
    }

    /// Marks setup's model step done and closes the Connect screen.
    private func modelDidConnect() {
        if let kind = accountStore.activeAccount?.kind { setup?.modelDidConnect(kind) }
        connectWindow?.close()
        connectWindow = nil
    }

    /// Gives the Dock back its original layout; runs on every quit.
    func stop() {
        gapReserver.releaseGap()
    }
}
