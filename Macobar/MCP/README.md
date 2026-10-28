# MCP
Shares Macie's tools with AI apps the user already has (Claude Code, Codex, Claude Desktop) over the Model Context Protocol: their model does the thinking, macobar does the doing. Off until the user turns it on.

## Files
- `MCPServer.swift`: listens on `127.0.0.1:7766` with `NWListener`; `start(onFailure:)` / `stop()`; serves at most 32 connections at once.
- `MCPConnection.swift`: one connection: reads one HTTP request, sends the answer, closes; closed if the request hasn't fully arrived within 10 s. Also `MCPConnectionLimit`, which counts open connections and turns new ones away at the limit.
- `HTTPRequest.swift`: reads an HTTP/1.1 request from bytes: `Content-Length` bodies only, headers ≤ 16 KB, body ≤ 1 MB (tested). Also `HTTPRequestError`.
- `HTTPResponse.swift`: a status, headers and body, written with `Content-Length` and `Connection: close` (tested).
- `MCPEndpoint.swift`: the HTTP rules: `Origin` and `Host` checks, path, bearer token, POST only, then the JSON-RPC answer in the request's `Mcp-Session-Id` session or a new one (tested).
- `MCPRequestHandler.swift`: JSON-RPC 2.0: `initialize`, `ping`, `tools/list`, `tools/call`; notifications get no reply; the approval policy and the one-line action shown in the Dock (tested). Also `MCPApprover`, the closure that asks the user in the Dock.
- `MCPClientNames.swift`: the name each app gave at `initialize` (its `title`, else its `name`, with Claude Code, Claude Desktop and Codex made readable), by session (up to 64, oldest dropped), cut to one line of 40 characters with control and invisible formatting characters removed. A name containing "macie" or "macobar", even in lookalike letters, is ignored, so the app shows as "An AI app". `visible(_:)` is shared with the action line (tested).
- `MCPSessionGrants.swift`: the tools the user chose Always Allow for, by MCP session and at the risk they saw (up to 64 sessions, oldest dropped). Never saved and never shared with Macie's `ToolApprovals` (tested).
- `MCPAccessToken.swift`: the token: 32 random bytes as hex, made once and kept in the Keychain as `mcpToken`.
- `ToolSharingModel.swift`: the on/off switch (preference `sharesToolsWithAIApps`, off by default), the token, and why sharing failed.
- `ToolSharingView.swift`, `ToolSharingWindow.swift`: the charcoal Share Tools window: switch, then address, token, Claude Code command and Claude Desktop config, each with Copy. Copied secrets are marked `org.nspasteboard.ConcealedType` so clipboard managers skip them.

## Public surface
- `ToolSharingModel(tools:approver:keychain:)`, `startIfEnabled()`, `isEnabled`, `token`, `failure`
- `MCPApprover`: `(ApprovalRequest, appName) async -> ApprovalDecision`; the app passes `ChatBarModel.requestApproval(_:from:)`
- `ToolSharingWindow(model:)`, `show()`
- `MCPRequestHandler(tools:version:approvalTimeout:approver:)` (`approvalTimeout` defaults to 2 minutes)
- `MCPServer.address` (`http://127.0.0.1:7766/mcp`)

## Transport
Minimal Streamable HTTP (MCP 2025-06-18): `POST /mcp` with one JSON-RPC message, answered as `application/json` (no SSE). A notification gets `202` with no body. `GET` and other methods on `/mcp` (including `DELETE` to end a session) are `405`; other paths `404`. Batches are refused with `-32600`.
Every answer carries `Mcp-Session-Id`: the one the request sent (if it is visible ASCII, as MCP requires), or a new one. Sessions tell apps apart for the approval prompt and scope Always Allow; the token is what grants access, and an unknown session is simply an unnamed app with no Always Allow choices.

## Safety
- Bound to 127.0.0.1 and local-only, so nothing off this Mac can connect.
- Every request needs `Authorization: Bearer <token>` (`401` otherwise; compared in constant time).
- A request with an `Origin` that isn't localhost is `403`, so a website can't reach in through DNS rebinding. So is a `Host` header that doesn't name `127.0.0.1`, `localhost` or `::1`.
- At most 32 connections at once; a request must arrive in full within 10 s.
- `run_shell` and `run_applescript` are never listed or run; the apps have shells of their own.
- Only a few harmless tools run without asking, and only when their risk is `.none`: `system_status`, `list_running_apps`, `list_shortcuts`, `music`, `control_app`, `arrange_window`. Every other tool asks in the Dock, including everything that reads files, the clipboard, the screen, windows, contacts, calendar, notes or the browser tab, and `set_timer`, whose notification would show the app's text as Macie's.
- Allow runs the call once. Always Allow (not offered for `.confirmEveryTime`) covers that tool at that risk only for the app's MCP session, until it reconnects, and is not saved; the card says so. Macie's own saved Always Allow never applies to apps, and an app's Always Allow never applies to Macie, because an app's model may be steered by anything it read.
- The action line in the Dock is flattened to one visible line (no line breaks or invisible formatting characters); anything over 300 characters keeps its first and last 150.
- The reply card says who is asking ("Claude Code wants to:", or "An AI app wants to:" when the app gave no name) above the usual Allow / Always Allow / Deny.
- Deny, Escape, or no answer within 2 minutes declines: the app gets an error result saying the user didn't allow it and not to retry.
- `VisualTool`s return their images as MCP image content.

## Connecting apps
- Claude Code: the window's Copy button gives `claude mcp add --transport http macobar http://127.0.0.1:7766/mcp --header "Authorization: Bearer <token>"`.
- Codex: `codex mcp add macobar --url http://127.0.0.1:7766/mcp --bearer-token-env-var MACOBAR_TOKEN`, with the token in that variable.
- Claude Desktop only runs local servers over stdio: the window's Copy button gives the `mcpServers` entry that launches `macobar-mcp`, the bridge inside the app (`Contents/MacOS/macobar-mcp`, from `MCPBridge/`), with the token in `MACOBAR_TOKEN`. Paste it into Settings → Developer → Edit Config and restart Claude Desktop.

## Gotchas
- One request per connection (`Connection: close`); MCP clients reconnect for each, which is cheap on localhost.
- Chunked request bodies are refused with `411`; MCP clients send `Content-Length`.
- If port 7766 is taken, the window says so and the switch stays on; turning it off and on retries.
- `stop()` stops new connections; requests already running finish.
- Only approvals show in the Dock; the silent tools (`system_status`, `list_running_apps`, `list_shortcuts`, `music`, `control_app`, `arrange_window`) leave no trace there.
- A client that doesn't resend `Mcp-Session-Id` is asked on every call, since Always Allow is per session.
- An approval waits behind a chat reply in progress, and several wait in order, each counting down its own 2 minutes. While the Dock is hidden the card can't be seen, so a request may time out.
- Apps may stop waiting sooner than 2 minutes; allowing after that still runs the action, but the app never sees the result.
- An app's name is whatever it says it is; the token, not the name, is what's trusted.

## Tested by
`MacobarTests/MCPServerTests.swift` (HTTP, JSON-RPC, token) and `MacobarTests/MCPApprovalTests.swift` (approval policy, session grants, app names, action lines, sessions, and the Dock's approval queue).

## Depends on
Tools (`Tool`, `ToolInput`, `ToolRisk`, `VisualTool`), ChatBar (`ApprovalRequest`, `ApprovalDecision`), ModelClient (`JSONValue`, `ToolImage`), Providers (`KeychainStore`), Setup (`SetupStyle`, `SetupButtonStyle`), Brand (`Macie`).
