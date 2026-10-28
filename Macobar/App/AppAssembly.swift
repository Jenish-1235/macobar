import AppKit

/// Builds every module and connects them; the only place concrete types meet.
@MainActor
final class AppAssembly {
    /// Keeps the spacer gap in the Dock.
    private let gapReserver = DockGapReserver()
    /// Reports where the Dock and the gap are.
    private let dockObserver = DockObserver(reader: DockReader())
    /// The saved providers and their keys.
    private let accountStore = ProviderAccountStore()
    /// Draws Macie's temporary marks over every screen.
    private let screenOverlay = ScreenOverlay()
    /// The window Macie shows diagrams in.
    private let diagramWindow = DiagramWindow()
    /// Keeps the document index that search_documents uses up to date.
    private let knowledgeIndexer = KnowledgeIndexer()
    /// Connects the user's MCP servers and runs their tools.
    private let mcpServers = MCPClientHub()
    /// Reads Macie's replies aloud when the user turns it on.
    private let spokenReply = SpokenReply()
    /// The chat's state: Macie answers with the fast or main model, and other apps' approvals queue here.
    private lazy var chatModel = ChatBarModel(responder: makeAgent(), spokenReply: spokenReply)
    /// Shows the field and reply sheet over the gap.
    private lazy var chatBar = ChatBarController(model: chatModel, onCommand: { [weak self] in self?.perform($0) })
    /// Runs scheduled prompts with a Macie of its own that starts fresh each run, so they never mix into the chat or steer each other.
    private lazy var scheduler = TaskScheduler(responder: makeAgent(remembersConversation: false))
    /// Shares Macie's tools with AI apps on this Mac when the user turns it on; risky calls ask in the Dock.
    private lazy var toolSharing = ToolSharingModel(
        tools: makeCatalog().shareable,
        approver: { [chatModel] request, appName in await chatModel.requestApproval(request, from: appName) }
    )
    /// The Option-Space shortcut: tap to type, hold to talk.
    private lazy var voice = VoiceController { [weak self] event in self?.handleVoice(event) }
    /// Setup state, kept to mark step 3 done.
    private var setup: SetupModel?
    /// The setup window, kept alive while it's open.
    private var setupWindow: SetupWindow?
    /// The Connect screen, kept alive while it's open.
    private var connectWindow: ConnectWindow?
    /// The Share Tools window, kept alive while it's open.
    private var toolSharingWindow: ToolSharingWindow?
    /// The Connections window, kept alive while it's open.
    private var connectionsWindow: ConnectionsWindow?
    /// The History window, kept alive while it's open.
    private var historyWindow: HistoryWindow?

    /// Restores the gap if the user added macobar before, shows setup if anything is missing, then keeps the chat bar pinned to the gap.
    func start() async {
        if gapReserver.wasAddedByUser { await restoreGap() }
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
        scheduler.start()
        toolSharing.startIfEnabled()
        Task { [knowledgeIndexer, mcpServers] in
            await knowledgeIndexer.refreshIfIndexed()
            _ = await mcpServers.tools()
        }
        await AccessibilityPermission.waitUntilGranted()
        voice.start()
        for await geometry in dockObserver.geometryUpdates() {
            chatBar.follow(geometry)
        }
    }

    /// Stops background work and gives the Dock back its original layout; runs on every quit.
    func stop() {
        voice.stop()
        scheduler.stop()
        mcpServers.stop()
        gapReserver.releaseGap()
    }

    /// A Macie with every built-in tool plus the connected MCP servers' tools.
    private func makeAgent(remembersConversation: Bool = true) -> Agent {
        Agent(
            accountStore: accountStore,
            tools: makeCatalog().all,
            promptTools: { [mcpServers] in await mcpServers.tools() },
            remembersConversation: remembersConversation
        )
    }

    /// Every built-in tool, sharing the one overlay, diagram window and document index but with screen marks of its own, so one runner (chat, scheduler, MCP) can't change what another's approved click lands on.
    private func makeCatalog() -> ToolCatalog {
        ToolCatalog(overlay: screenOverlay, diagrams: diagramWindow, knowledge: knowledgeIndexer)
    }

    /// Puts the gap back once the Dock has settled, checking again after it restarts: a Dock still starting up can save its old layout over the gap.
    private func restoreGap() async {
        for _ in 0..<3 {
            await DockProcess.waitUntilSettled()
            gapReserver.reserveGap(width: ChatBarStyle.preferredFieldWidth)
            await DockProcess.waitUntilSettled()
            if gapReserver.isGapReserved { return }
        }
    }

    /// Runs an item from the field's right-click menu.
    private func perform(_ command: ChatBarCommand) {
        switch command {
        case .changeModel: showConnect(over: nil)
        case .connections:
            connectionsWindow = connectionsWindow ?? ConnectionsWindow(model: ConnectionsModel(hub: mcpServers))
            connectionsWindow?.show()
        case .shareTools:
            toolSharingWindow = toolSharingWindow ?? ToolSharingWindow(model: toolSharing)
            toolSharingWindow?.show()
        case .history:
            historyWindow = historyWindow ?? HistoryWindow(model: HistoryModel())
            historyWindow?.show()
        case .quit: NSApp.terminate(nil)
        }
    }

    /// Applies the voice shortcut's events to the chat bar.
    private func handleVoice(_ event: VoiceEvent) {
        switch event {
        case .focusField:
            chatModel.stopSpeaking()
            chatBar.focusField()
        case .listening:
            chatModel.stopSpeaking()
            chatModel.isHearingVoice = true
        case .transcript(let text): chatModel.draft = text
        case .status(let text): chatModel.showNotice(text)
        case .finished(let prompt):
            chatModel.isHearingVoice = false
            if prompt == nil { chatModel.draft = "" } else { chatModel.submit() }
        case .failed(let message):
            chatModel.isHearingVoice = false
            chatModel.showNotice(message)
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
}
