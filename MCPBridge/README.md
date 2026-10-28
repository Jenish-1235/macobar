# MCPBridge
`macobar-mcp`: a tiny command-line tool that lets apps which only run local MCP servers over stdio (Claude Desktop) use Macie's tools. It relays each message to macobar's HTTP endpoint and prints the answer.

## Files
- `main.swift`: reads newline-delimited JSON-RPC from stdin, POSTs each message to `http://127.0.0.1:7766/mcp` with `Authorization: Bearer $MACOBAR_TOKEN`, and writes each answer as one line to stdout. A notification (`202`) gets no line. Keeps the `Mcp-Session-Id` macobar hands out, so the Dock can say "Claude Desktop wants to:". Uses its own ephemeral `URLSession` with proxies off, so the token only ever goes to 127.0.0.1.

## Setup
The tool ships inside the app at `Macobar.app/Contents/MacOS/macobar-mcp`. In macobar, right-click the field → **Share Tools with AI Apps…**, turn sharing on, and copy the Claude Desktop config. In Claude Desktop, open Settings → Developer → Edit Config, add the entry, and restart Claude Desktop:

```json
{
  "mcpServers": {
    "macobar": {
      "command": "/Applications/Macobar.app/Contents/MacOS/macobar-mcp",
      "env": { "MACOBAR_TOKEN": "<token from the Share Tools window>" }
    }
  }
}
```

## Environment
- `MACOBAR_TOKEN` (required): the token from the Share Tools window. Without it the tool says so on stderr and exits with status 1. Passing it in the environment means the bridge never touches the Keychain.

## Errors
A request that can't be answered gets a JSON-RPC error (`-32000`) saying how to fix it: macobar isn't running or sharing is off, the token was refused (copy the config again), or macobar's own refusal.

## Gotchas
- Messages are relayed concurrently, so a ping isn't held up by a tool call waiting for approval in the Dock; answers are written one whole line at a time.
- Each request waits up to 3 minutes, longer than macobar's 2-minute approval window, so macobar decides.
- Closing stdin ends the tool; answers still in flight are dropped, since nobody is listening.

## Depends on
macobar's `MCP/` server (on, with the token). Foundation only.
