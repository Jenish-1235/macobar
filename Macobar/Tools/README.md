# Tools
Everything Macie can do on the Mac. Each tool describes itself to the model, says how risky a call is and whether its result carries outside text, and does the work.

## Files
- `Tool.swift`: the `Tool` protocol (`risk(for:)`, `readsOutsideContent(for:)`, `activity(for:)`, `run`), `VisualTool` (returns images too, via `look`), `ToolRisk` and `ToolError`.
- `ToolInput.swift`: typed access to a call's arguments (numbers too large for an `Int` read as missing). `Schema.swift`: builders for argument schemas.
- `ToolCatalog.swift`: the tools handed to an agent (`all`), the subset shared with other AI apps over MCP (`shareable`), and `sendsDataOut` (tools that can carry data off the Mac). A catalog holds one `ScreenMarkStore`; each runner gets its own catalog.
- `Support/`: `ProcessRunner` (runs programs, combined output kept to the last 8 MB, timeout), `AppleScript` (runs `osascript` with values passed as `argv`), `RunningApps` (find apps by name), `AccessibilityElement` (read and act on other apps' UI), `ProtectedLocations` (places file changes refuse, and private places that ask every time), `PublicNetworkAddress` (fetch targets must resolve to public IPs), `RedirectRefuser` (never follow redirects).
- One file per area: `AppTools`, `ScreenTools`, `VisionTools`, `ScreenControlTools`, `OverlayTools`, `DiagramTool`, `GuideTools`, `WindowTools`, `InAppTools`, `SelectionTools`, `FileTools`, `KnowledgeTools`, `WebTools`, `BrowserTools`, `ClipboardTool`, `ShortcutsTools`, `SystemTools`, `TimerTool`, `ScheduleTools`, `CalendarTools`, `ContactsTool`, `CommunicationTools`, `MusicTool`, `MemoryTools`, `ActivityTools`, `SandboxTools`, `ScriptTools`.

## The tools
| Risk | Tools |
|---|---|
| Runs without asking | `open_app`, `list_running_apps`, `control_app` (activate, hide), `get_frontmost_context`, `read_window_text`, `arrange_window`, `list_ui_elements`, `view_image`, `draw_on_screen`, `point_at_element`, `point_at_mark`, `clear_screen_drawings`, `show_diagram`, `wait_for_user`, `search_files`, `open_file` (documents), `read_file` (non-private paths), `search_documents`, `index_documents`, `fetch_web_page` (public sites), `open_url` (web, mail, Settings links), `get_browser_tab`, `read_page`, `list_shortcuts`, `system_status`, `system_control` (volume, appearance), `set_timer`, `list_scheduled_tasks`, `list_events`, `list_reminders`, `find_contact`, `compose_email` (draft), `notes` (search), `music`, `recent_activity` |
| Asks once, then Always Allow | `take_screenshot`, `read_screen_text`, `look_at_screen`, `click_mark`, `scroll`, `drag`, `click_element`, `click_menu_item`, `type_text`, `press_keys`, `replace_selection`, `control_app` (quit), `manage_file` (create folder, move, copy, write new file), `fetch_web_page` (localhost, local-network names, bare IPs), `clipboard`, `click_on_page`, `fill_on_page`, `run_shortcut`, `system_control` (lock, sleep display), `create_event`, `create_reminder`, `notes` (create), `remember`, `forget`, `cancel_scheduled_task`, `undo_last_action`, `run_in_sandbox` (code only) |
| Asks every time | `schedule_task`, `send_message`, `compose_email` (send), `manage_file` (trash, overwrite, private paths), `read_file` (private paths such as ~/Library and hidden files), `open_file` (anything that can run code: apps, scripts, installers, link files), `open_url` (other schemes), `type_text` (into a password field), `run_page_script`, `run_in_sandbox` (with your files), `run_applescript`, `run_shell` |
| Refused | `manage_file` and undo on protected places: system folders, your home folder itself, ~/Library/Keychains, ~/Library/LaunchAgents, ~/Library/Application Support/macobar, ~/.ssh, macobar's preferences and app bundle, the inside of any app |

Two rules sit on top of each tool's risk (in `Agent/ContentExposure.swift`):
- Once a tool that `readsOutsideContent` has run (pages, files, screens, mail, calendar, contacts, shell output, MCP servers and more, about 30 tools), Always Allow stops counting for as long as that text is in the conversation.
- Once private text could be in the conversation, the `sendsDataOut` tools (`fetch_web_page`, `open_url`) ask, with no Always Allow.

## Adding a tool
1. Write a `struct` conforming to `Tool` in the file for its area: a snake_case `name`, a short `description` that says when to call it (and which tool to prefer instead) and what it returns, `parameters` built with `Schema`, a present-tense `activity` that shows what will happen ("Typing “hello” into Notes"), and `run` returning short plain text.
2. Override `risk(for:)` if it changes anything or exposes private data, and `readsOutsideContent(for:)` if its result carries text someone else could have written. Throw `ToolError` with a fix-it message on failure. To show the model images, conform to `VisualTool` and implement `look` instead of `run`.
3. Add it to `ToolCatalog.all`; add its name to `notShared` if other AI apps mustn't get it, or to `sendsDataOut` if it can carry data off the Mac.
4. Keep descriptions short: every request sends every definition, and long ones cost rate limit and make local models less reliable.

## Permissions
- Accessibility (granted in setup): screen context, windows, `InAppTools`, screen marks and the real mouse, `replace_selection`, guide mode, `lock_screen`.
- Screen Recording (Privacy & Security → Screen & System Audio Recording) for `take_screenshot`, `read_screen_text` and `look_at_screen`; the first use asks, and macOS asks again monthly.
- Automation prompts, per target app: browser tab and page tools, Mail, Messages, Notes, Music, System Events, `run_applescript`. Browsers also need their own "Allow JavaScript from Apple Events" switch for the page tools; the tool says how.
- Calendars, Reminders, Contacts prompts on first use. Notifications prompt on the first timer or finished scheduled task.
- `run_in_sandbox` needs Apple's `container` CLI (github.com/apple/container) with `container system start` run once; macobar never installs or starts it.
- macobar is not sandboxed; `mdfind`, `shortcuts`, `osascript`, `pmset` and the shell need that.

## Gotchas
- Never splice model text into AppleScript, shell or JavaScript source; pass it as arguments (`on run argv`, `$1`, JSON literals).
- Tools that type, click or read UI refuse macobar's own windows, so Macie can't approve herself. Password fields are never read, and typing into one asks every time without showing the text.
- `type_text` and `press_keys` post events straight to the target app's process; `click_mark`, `scroll` and `drag` move the real pointer and put it back.
- Element ids from `list_ui_elements` last until that window changes; mark numbers from `look_at_screen` last 2 minutes or until the next look.
- Drawing tools take points from the top-left of the main screen; each drawing replaces the last and fades out. Every label starts with Macie's face, so it can't pass for system UI.
- `fetch_web_page` reaches public addresses only, follows at most 5 checked redirects, and stops at 5 MB. `read_file` reads HTML without WebKit and refuses devices and pipes.
- `search_documents` and `index_documents` embed text with a server on this Mac only (LM Studio by default).
- `manage_file`'s result lines ("Moved to …", "Copied to …", "Trash location: …") are parsed by `Activity/` for undo; keep them as they are.
- Scheduled tasks run with no one watching, so every approval request in them is declined. They can't schedule more tasks.
- Over MCP (`MCP/`) other apps get the tools in `shareable`. Harmless ones run silently; everything else asks in the Dock, naming the app; Always Allow there lasts one session. `run_shell` and `run_applescript` are withheld.
- Tools from connected MCP servers (`MCPClient/`) join each prompt as `RemoteTool`s named `<server>__<tool>`; a built-in tool wins a name clash.
- `macobar-bench` offers every tool here with its real name, description, parameters and risk but never runs it.

## Depends on
ModelClient (`JSONValue`, `ToolDefinition`, `ToolImage`), Agent (`MacieMemory`), Overlay, Diagram, Grounding, Guide, Knowledge, Schedule, Activity.
