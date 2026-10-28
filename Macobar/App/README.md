# App
Entry point and wiring. The only module that knows every concrete type.

## Files
- `MacobarApp.swift`: `@main` entry that runs AppKit, plus the `AppDelegate` that starts the assembly and stops it on quit.
- `TerminationSignals.swift`: turns SIGTERM and SIGINT into a normal quit, so cleanup still runs.
- `AppAssembly.swift`: builds every module once (one `ScreenOverlay`, `KnowledgeIndexer`, `MCPClientHub`, `SpokenReply`, `ToolCatalog`), shows setup when needed, routes the field's menu commands and voice events, and feeds Dock geometry to the chat bar.

## Startup order
1. Restore the Dock gap if the user added macobar before, once the Dock has settled (checked again after it restarts, up to 3 tries).
2. Show the setup window if Accessibility access, the Dock gap or a connected model is missing; its step 3 opens the Connect sheet.
3. Start the `TaskScheduler` (with its own `Agent`, so scheduled prompts never touch the chat's conversation) and tool sharing over MCP if the user left it on; its approver is `ChatBarModel.requestApproval(_:from:)`, so other apps' risky calls ask in the Dock.
4. In the background: refresh the document index if the user built one, and connect the MCP servers in Connections so the first prompt doesn't wait for them.
5. Wait for Accessibility access, then register the Option-Space shortcut (`VoiceController`): tap focuses the field, hold transcribes speech into it and sends it on release.
6. Forward every `DockGeometry` update to `ChatBarController.follow(_:)`.

Replies always come from an `Agent` (Macie) with every tool in `ToolCatalog` plus the connected MCP servers' tools, so a model connected from setup or Change Model… is used from the next prompt.

## Windows
Change Model… (Connect), Connections…, Share Tools with AI Apps… and History… each open one window, kept alive while open. The `macobar-mcp` bridge (MCPBridge/) is built as its own target and copied into Contents/MacOS.

## Quitting
Every way out (Quit in the field's menu, closing setup early, logout, `kill`, Ctrl-C) goes through `applicationWillTerminate`: it stops voice input, the scheduler and the MCP server processes, then removes the Dock gap.

## Depends on
Every module.
