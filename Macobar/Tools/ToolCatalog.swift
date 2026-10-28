/// Every tool Macie can use, built around the app's one drawing overlay, diagram window and document index.
struct ToolCatalog {
    /// Tools other AI apps must not get over MCP: Macie's own memory, schedule and history; drawing on the screen or in a window (an app could fake a prompt); and the signed-in browser tab.
    private static let notShared: Set = [
        "remember", "forget", "schedule_task", "list_scheduled_tasks", "cancel_scheduled_task",
        "undo_last_action", "recent_activity", "draw_on_screen", "point_at_element", "clear_screen_drawings",
        "read_page", "run_page_script", "index_documents", "point_at_mark", "wait_for_user", "show_diagram",
    ]

    /// Tools that send text the model chose off the Mac without asking (a URL carries anything), so they ask once private text is in the conversation.
    static let sendsDataOut: Set = ["fetch_web_page", "open_url"]

    /// Where the drawing tools draw.
    let overlay: ScreenOverlay
    /// The window show_diagram draws in.
    let diagrams: DiagramWindow
    /// The document index the knowledge tools search.
    let knowledge: KnowledgeIndexer
    /// The numbered marks from the latest look_at_screen, shared by the tools that point at or act on them.
    let marks = ScreenMarkStore()

    /// All tools, grouped by area.
    var all: [any Tool] {
        [
            // Apps, screen and windows
            OpenAppTool(), ControlAppTool(), ListAppsTool(),
            FrontmostContextTool(), ReadWindowTool(), ArrangeWindowTool(),
            TakeScreenshotTool(), ReadScreenTextTool(), ViewImageTool(),
            // Seeing the screen as numbered marks, and the real mouse
            LookAtScreenTool(marks: marks), ClickMarkTool(marks: marks), ScrollTool(marks: marks), DragTool(marks: marks),
            // Drawing on the screen and in diagrams, and guiding the user step by step
            DrawOnScreenTool(overlay: overlay), PointAtElementTool(overlay: overlay), PointAtMarkTool(overlay: overlay, marks: marks),
            ClearScreenDrawingsTool(overlay: overlay), WaitForUserTool(), ShowDiagramTool(window: diagrams),
            // Inside apps
            ListUIElementsTool(), ClickElementTool(), ClickMenuItemTool(), TypeTextTool(), PressKeysTool(), ReplaceSelectionTool(),
            // Files, documents, web and clipboard
            SearchFilesTool(), OpenFileTool(), ReadFileTool(), ManageFileTool(),
            SearchKnowledgeTool(indexer: knowledge), IndexDocumentsTool(indexer: knowledge),
            OpenURLTool(), FetchWebPageTool(), BrowserTabTool(), ClipboardTool(),
            ReadPageTool(), ClickOnPageTool(), FillOnPageTool(), RunPageScriptTool(),
            // Automation and system
            ListShortcutsTool(), RunShortcutTool(), SystemStatusTool(), SystemControlTool(), SetTimerTool(),
            ScheduleTaskTool(), ListScheduledTasksTool(), CancelScheduledTaskTool(),
            // Personal data and communication
            ListEventsTool(), CreateEventTool(), ListRemindersTool(), CreateReminderTool(), FindContactTool(),
            ComposeEmailTool(), SendMessageTool(), NotesTool(), MusicTool(),
            // Macie's memory and history
            RememberTool(), ForgetTool(), RecentActivityTool(), UndoLastActionTool(),
            // Power tools
            RunInSandboxTool(), RunAppleScriptTool(), RunShellTool(),
        ]
    }

    /// Tools other AI apps may use over MCP.
    var shareable: [any Tool] {
        all.filter { !Self.notShared.contains($0.name) }
    }
}
