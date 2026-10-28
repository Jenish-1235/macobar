# macobar

A persistent agent for macOS that you talk to from a text field living inside the Dock.
macobar is the bar; **Macie** is the agent who lives in it.

## Build and run
Requires Xcode 27+, macOS 26+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make run    # generate the project, build, and launch
make test   # run the tests (the app's code, compiled without launching it)
make bench  # build macobar-bench, which scores a model on Macie's tasks (see MacobarBench/README.md)
```

On first launch a setup window walks through three steps: allowing **Accessibility** access (macobar needs it to read where the Dock is), adding an empty gap right after Finder (the Dock restarts once; the chat field sits in that gap), and connecting a model. Keys are kept in your Keychain and sent only to that provider; a local model in LM Studio or Ollama needs no key.

Using Macie:
- Type in the field, or press **Option-Space** from anywhere to focus it. Hold Option-Space to talk; what you say is transcribed on this Mac and sent when you let go.
- Macie acts with ~60 tools: apps and windows, the screen (as numbered marks she can point at and click), files and documents, web pages, mail, messages, calendar, Shortcuts, sandboxed code, the shell. She can draw on the screen to point things out and guide you step by step, waiting until you've done each step.
- Anything risky asks first in the card above the Dock. Once she has read outside content (a page, file, screen or email) in a task, she asks again even for actions you chose to Always Allow.

Right-click the field for:
- **Change Model…**: switch providers, or set a fast model (e.g. local) for quick commands next to the main one.
- **Connections…**: give Macie tools from MCP servers like GitHub, Linear or Notion (she asks before using them unless you trust the server; secrets stay in your Keychain).
- **Share Tools with AI Apps…**: let Claude Code, Codex or Claude Desktop use Macie's tools over MCP (off by default; shell, AppleScript, drawing, memory and your browser tab are never shared, and anything risky asks in the Dock, naming the app).
- **History…**: everything Macie did, with Undo for file changes.
- **Speak Replies**: Macie reads her answers aloud.
- **Quit macobar**. The gap is there only while macobar runs: any quit removes it, and the next launch puts it back. After a force quit or crash, drag the empty spacers out of the Dock, or launch and quit macobar once.

## How it works
1. `Setup/` asks for permission and has `Dock/` add spacer tiles after Finder; `Dock/` then reads their on-screen frame through Accessibility.
2. `ChatBar/` pins a transparent panel with the text field exactly over that gap, and a reply sheet just above the Dock. `Voice/` adds the Option-Space shortcut; `Speech/` reads replies aloud.
3. `Agent/` (Macie) picks the fast or main model with `Routing/`, sends the prompt through `ModelClient/`, runs the `Tools/` the model asks for (plus tools from `MCPClient/`), asks you first for anything risky, records each action in `Activity/`, and streams what she says and does to the reply card.
4. Tools build on `Grounding/` (numbered screen marks and the real mouse), `Overlay/` (drawing on the screen), `Diagram/` (Mermaid diagrams in a window), `Guide/` (waiting for the user's step), `Knowledge/` (document search with a local embeddings model) and `Schedule/` (prompts that run later or on repeat).
5. `MCP/`, when turned on, serves the same tools to other AI apps on this Mac.
6. `App/` wires the modules together.

## Modules
| Folder | Job |
|---|---|
| `Macobar/App` | Entry point and wiring; the only place concrete types meet |
| `Macobar/Dock` | Reserves the gap in the Dock and reports where it is |
| `Macobar/ChatBar` | The field in the Dock, its menu, and the reply sheet above it |
| `Macobar/Setup` | The setup window and the Connect screen for choosing the main and fast models |
| `Macobar/Providers` | Model providers (cloud and local), their endpoints, and credentials in the Keychain |
| `Macobar/ModelClient` | Streams replies, tool calls and images in each provider's API format |
| `Macobar/Agent` | Macie: the loop that runs tools until a task is done, with approvals, memory and instructions |
| `Macobar/Routing` | Picks the fast or main model for each prompt, and when to hand over |
| `Macobar/Tools` | The ~60 things Macie can do on the Mac, grouped by area |
| `Macobar/Grounding` | Sees the screen as numbered marks (Accessibility + OCR) and drives the real mouse |
| `Macobar/Overlay` | Macie's temporary, animated drawings on the screen |
| `Macobar/Guide` | Guide mode: waits until the user does the step Macie points at |
| `Macobar/Knowledge` | Searches documents by meaning with a local embeddings model; the index stays on the Mac |
| `Macobar/Activity` | Records every action, the History window, and undo for file changes |
| `Macobar/Schedule` | Prompts Macie runs later or on repeat, results shown as notifications |
| `Macobar/Voice` | The Option-Space shortcut: tap to type, hold to talk (on-device speech) |
| `Macobar/Speech` | Reads Macie's replies aloud, sentence by sentence; off by default |
| `Macobar/MCP` | Shares Macie's tools with AI apps on this Mac over MCP; off by default |
| `Macobar/MCPClient` | Uses tools from MCP servers the user connects, set up in Connections… |
| `Macobar/Permissions` | Checks and requests Accessibility access |
| `Macobar/Brand` | Macie, the character shared by every screen |
| `MCPBridge` | `macobar-mcp`, the stdio bridge Claude Desktop launches to reach the MCP server |
| `MacobarBench` | `macobar-bench`: scores how well a model drives Macie's tools, with stand-in tools so nothing on the Mac is touched |
| `MacobarTests` | Tests for the app's logic (no app launch) |
| `site` | The landing page: static HTML/CSS/JS, no build step |

Each folder has its own README. When a module changes, its README changes in the same edit.

## Code principles
- One type, one job; small files. Protocols only where a second implementation or a test needs one.
- Build only what the current milestone needs (YAGNI).
- Descriptive names, no `Manager`/`Helper`/`Utils`.
- A one-line `///` comment on every type, function and property; no comments that restate code.
- Swift 6 strict concurrency, value types by default, `private` by default, no force-unwraps.
