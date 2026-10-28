# MCPClient
Lets Macie use the tools of MCP servers the user connects (GitHub, Linear, Notion, Playwright, a filesystem server…), next to her own. The mirror image of `MCP/`, which shares Macie's tools with other apps.

## Files
- `MCPServerConfig.swift`: one server: unique name (lowercase letters, digits and hyphens, not starting or ending with a hyphen and never two in a row, so tool names from different servers can never collide), transport (`command` with arguments, or `address` URL) and whether it's trusted (off by default). `isAllowedAddress(_:)`: https anywhere, http only to `localhost`, `127.0.0.1` or `::1`.
- `MCPServerStore.swift`: the servers in `~/Library/Application Support/macobar/mcp-servers.json` (no secrets): list, add (refuses a malformed or taken name), remove, set trusted; atomic writes (tested).
- `MCPServerSecrets.swift`: each server's environment variables (command) or headers (address) as one JSON Keychain item, `mcp-server.<name>`; also reads the form's `KEY=value` lines (tested).
- `CommandLineWords.swift`: splits the typed command line into words with shell-style quotes and `\` escapes, without a shell (tested).
- `MCPTransport.swift`: the transport contract: request (waits for the reply to its id), notify, `isOpen`, close.
- `StdioTransport.swift`: runs the command through `/usr/bin/env` with only `HOME`, `LOGNAME`, `USER`, `SHELL`, `TMPDIR`, `LANG`, `LC_ALL`, `LC_CTYPE` and `__CF_USER_TEXT_ENCODING` from macobar's environment, plus the user's login `PATH` (from `/bin/zsh -lc 'echo $PATH'`, read once) and the server's secrets. `SSH_AUTH_SOCK` and API keys are not passed. Newline-delimited JSON-RPC on stdin/stdout, stderr discarded; a line over 32 MB ends the connection (tested).
- `StreamableHTTPTransport.swift`: POSTs each message with the server's headers; reads an `application/json` body or a `text/event-stream`; keeps `Mcp-Session-Id`. Uses its own ephemeral session with no cookies and no cache. Refuses plain http to another computer. Bodies and lines are capped at 32 MB; `notify` doesn't read the body. Also `SameOriginRedirects`: redirects are followed only to the same scheme, host and port; anything else fails with the 3xx status (tested).
- `JSONRPC.swift`: building requests, matching replies, reading JSON bodies. `value(fromJSON:)` refuses JSON over 32 MB, nested more than 64 levels (deeper nesting overflows the stack while decoding) or in UTF-16/UTF-32 (tested).
- `ServerSentEventReader.swift`: reads messages from an event stream: a single `data:` line is parsed at once, a multi-line event when its blank line arrives; each event is capped at 32 MB (tested).
- `NewlineSeparatedLines.swift`: splits stdout and event streams at `\n` only, keeping blank lines; Foundation's `lines` also splits at U+2028/U+2029, which Node servers send raw inside JSON strings (tested).
- `MCPClient.swift`: one session: `initialize` (protocol 2025-06-18, client "macobar") and `notifications/initialized`, `tools/list` following `nextCursor` (at most 50 pages, at most 256 tools kept), `tools/call`.
- `MCPToolInfo.swift`: reading a tools/list page: descriptions are cut to 2,048 characters; tools with a name over 128 characters or a schema over 64 KB are left out (tested).
- `MCPToolOutput.swift`: reading a tools/call result: text joined (structured content when there's no text), PNG, JPEG, GIF and WebP images up to 5 MB as `ToolImage` (other types and larger images dropped, since a provider would refuse the request), `isError` thrown as `ToolError` (tested).
- `MCPClientError.swift`: timeouts, HTTP statuses, a command that exited, server errors, messages too large, plain http to another computer; each says how to fix it.
- `RemoteToolName.swift`: `<server>__<tool>` made to fit `^[a-z0-9_]{1,64}$`; a longer name keeps 55 characters, then `_` and an FNV-1a hash of the whole name. `shown(_:)`: the server's tool name made safe for display (ASCII letters, digits, `_`, `-` and `.` only, at most 64 characters) (tested).
- `RemoteTool.swift`: a server's tool as a `VisualTool`: "From <server>: …" description, its input schema, activity "Using <tool> from <server>" with the tool name made safe, `.confirmOnce` unless the server is trusted (then `.none`); its results count as outside content.
- `MCPClientHub.swift`: the actor that connects servers when tools are first asked for, keeps each tool list (one tool per name; when two names clash, the server added first wins), records each server's status, runs calls, and stops every process on quit.
- `ConnectionsModel.swift`, `ConnectionsView.swift`, `ConnectionsWindow.swift`: the charcoal Connections window: servers with their status and Trust, Test and Remove; a form to add one (name, Command or Address, optional `KEY=value` secrets). Removing a server also revokes its tools' Always Allow choices (`ToolApprovals.revoke(namesStartingWith:)`), so they don't carry over to a new server with the same name.

## Public surface
- `MCPClientHub(store:secrets:)`: `tools() async -> [any Tool]`, `test(_:)`, `disconnect(serverNamed:)`, `statuses`, `stop()` (nonisolated, synchronous)
- `ConnectionsModel(hub:)`, `ConnectionsWindow(model:)`, `show()`
- `MCPServerStore(fileURL:)`, `MCPServerSecrets(keychain:)`

## How servers connect
1. `tools()` reads the servers and their secrets fresh each time and connects every server not yet connected, all at once. Servers that fail are skipped, and their failure shows in Connections.
2. A server is connected afresh when its command, address or secrets change, when its process has died or its HTTP session ended, or when Test is pressed. A removed server is disconnected, and its tools' Always Allow choices are revoked (`ToolApprovals.revoke(namesStartingWith:)` with its `<server>__` prefix). Changing Trust doesn't reconnect.
3. A server that failed to connect is tried again after five minutes, or at once when Test is pressed or its settings change, so a hung server doesn't slow every prompt.
4. Calls go through the hub, so a server whose process died is restarted before the call.

## Safety
- Every remote tool asks first unless the user trusts its server. Remote tools' descriptions and results count as outside text, so while any server's tools are offered, Always Allow doesn't apply in that prompt (the Agent's rule) and only trusting the server stops the asking.
- Secrets live only in the Keychain; the JSON file has names, commands and addresses.
- The command is passed to `/usr/bin/env` as separate arguments, never through a shell.
- Remote tools aren't shared back out over `MCP/`.
- A tool's description and schema come from the server and are trimmed to fixed limits; every read is capped (32 MB a message, 64 levels of nesting) so a hostile server can't exhaust memory or crash macobar.
- Server processes run with macobar's privacy permissions (Accessibility, Automation and so on, through macOS's responsible-process rules), so connecting a command server means trusting that program as much as macobar.

## Gotchas
- Stdio requests time out after 30 seconds without a reply. HTTP requests time out after 30 seconds between bytes and 120 seconds for the whole exchange. A slow tool fails rather than hangs.
- The login `PATH` comes from `zsh -l`, which doesn't read `.zshrc`; tools set up only there (some nvm installs) need their full path.
- Plain `http://` addresses work only for servers on this Mac (`localhost`, `127.0.0.1`, `::1`); servers elsewhere, including on the local network, need `https://`.
- Servers that use git over SSH don't see `SSH_AUTH_SOCK` unless it's added as one of their secrets.
- Server-to-client requests (sampling, roots, elicitation) and notifications are ignored; macobar declares no client capabilities.
- `KeychainStore` can't delete yet, so removing a server overwrites its secrets with an empty set.
- Remote tools join Macie's own for each prompt (a built-in tool wins a name clash); a server that's slow to start delays the first prompt that needs it.

## Tested by
`MacobarTests/MCPClientTests.swift`.

## Depends on
Agent (`ToolApprovals`), Tools (`Tool`, `VisualTool`, `ToolInput`, `ToolRisk`, `ToolError`, `Schema`, `ProcessRunner`), ModelClient (`JSONValue`, `ToolImage`), Providers (`KeychainStore`), Setup (`SetupStyle`, `SetupButtonStyle`, `SetupTextField`), Brand (`Macie`).
