import Testing

/// Verifies when outside text stops Always Allow and makes sending data off the Mac ask, and the risks that rule relies on.
struct ContentExposureTests {
    /// Outside text from a tool that could hold private data.
    private static let privateText = ContentExposure(hasOutsideContent: true, hasPrivateContent: true)
    /// Outside text from a public page only.
    private static let publicText = ContentExposure(hasOutsideContent: true, hasPrivateContent: false)

    @Test("Before any outside text, risk-free and always-allowed tools run without asking")
    func cleanConversation() {
        let clean = ContentExposure()
        #expect(clean.runsWithoutAsking(risk: .none, isAlwaysAllowed: false, sendsDataOut: true))
        #expect(clean.runsWithoutAsking(risk: .confirmOnce, isAlwaysAllowed: true, sendsDataOut: false))
        #expect(!clean.runsWithoutAsking(risk: .confirmOnce, isAlwaysAllowed: false, sendsDataOut: false))
        #expect(!clean.runsWithoutAsking(risk: .confirmEveryTime, isAlwaysAllowed: true, sendsDataOut: false))
    }

    @Test("Once outside text is in, Always Allow no longer counts")
    func alwaysAllowStops() {
        #expect(!Self.publicText.runsWithoutAsking(risk: .confirmOnce, isAlwaysAllowed: true, sendsDataOut: false))
        #expect(Self.publicText.runsWithoutAsking(risk: .none, isAlwaysAllowed: false, sendsDataOut: false))
    }

    @Test("Sending data out asks once private text is in, but not after public pages alone")
    func sendingOutAsks() {
        #expect(Self.publicText.runsWithoutAsking(risk: .none, isAlwaysAllowed: false, sendsDataOut: true))
        #expect(!Self.privateText.runsWithoutAsking(risk: .none, isAlwaysAllowed: false, sendsDataOut: true))
        #expect(Self.privateText.runsWithoutAsking(risk: .none, isAlwaysAllowed: false, sendsDataOut: false))
    }

    @Test("A page fetched without asking adds public text; anything else that reads outside text adds private text")
    func adding() {
        let clean = ContentExposure()
        #expect(clean.adding(readsOutsideContent: false, sendsDataOut: false, risk: .none) == clean)
        #expect(clean.adding(readsOutsideContent: true, sendsDataOut: true, risk: .none) == Self.publicText)
        #expect(clean.adding(readsOutsideContent: true, sendsDataOut: true, risk: .confirmOnce) == Self.privateText)
        #expect(clean.adding(readsOutsideContent: true, sendsDataOut: false, risk: .none) == Self.privateText)
        #expect(Self.privateText.adding(readsOutsideContent: true, sendsDataOut: true, risk: .none) == Self.privateText)
    }

    @Test("Combining keeps everything either side has seen")
    func combining() {
        #expect(ContentExposure().combined(with: Self.publicText) == Self.publicText)
        #expect(Self.publicText.combined(with: Self.privateText) == Self.privateText)
    }

    @Test("The tools that send data out are the real web tools")
    func sendsDataOutNames() {
        #expect(ToolCatalog.sendsDataOut == [FetchWebPageTool().name, OpenURLTool().name])
    }

    @Test("Remembering, forgetting and scheduling ask, and scheduling asks every time")
    func persistentToolsAsk() {
        #expect(RememberTool().risk(for: ToolInput(["fact": "Prefers tea"])) == .confirmOnce)
        #expect(ForgetTool().risk(for: ToolInput(["id": "m1"])) == .confirmOnce)
        #expect(ScheduleTaskTool().risk(for: ToolInput(["prompt": "Hi", "at": "2030-01-01T08:00"])) == .confirmEveryTime)
    }

    @Test("Fetching a page doesn't ask, so its text counts as public; this Mac and the local network are refused instead")
    func pageFetchesRunFreely() {
        #expect(FetchWebPageTool().risk(for: ToolInput(["url": "https://example.com/page?q=1"])) == .none)
    }

    @Test("Tools that return names or labels others chose count as outside text")
    func outsideLabels() {
        #expect(BrowserTabTool().readsOutsideContent(for: ToolInput()))
        #expect(SearchFilesTool().readsOutsideContent(for: ToolInput(["query": "x"])))
        #expect(ListUIElementsTool().readsOutsideContent(for: ToolInput()))
        #expect(RecentActivityTool().readsOutsideContent(for: ToolInput()))
        #expect(ListScheduledTasksTool().readsOutsideContent(for: ToolInput()))
        #expect(FindContactTool().readsOutsideContent(for: ToolInput(["name": "Ann"])))
        #expect(RunInSandboxTool().readsOutsideContent(for: ToolInput()))
        #expect(RunShortcutTool().readsOutsideContent(for: ToolInput(["name": "x"])))
        #expect(ClickMenuItemTool().readsOutsideContent(for: ToolInput(["path": ["Window"]])))
        #expect(WaitForUserTool().readsOutsideContent(for: ToolInput(["expect": "window_change"])))
        #expect(!WaitForUserTool().readsOutsideContent(for: ToolInput(["expect": "any_key"])))
        #expect(MusicTool().readsOutsideContent(for: ToolInput(["action": "now_playing"])))
        #expect(!MusicTool().readsOutsideContent(for: ToolInput(["action": "pause"])))
    }
}
