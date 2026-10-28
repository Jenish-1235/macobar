# macobar

A persistent agent for macOS that you talk to from a text field living inside the Dock.
macobar is the bar; **Macie** is the agent who lives in it.

## Build and run
Requires Xcode 27+, macOS 26+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make run    # generate the project, build, and launch
make test   # run the logic tests
```

On first launch a setup window walks through three steps: allowing **Accessibility** access (macobar needs it to read where the Dock is), adding an empty gap right after Finder (the Dock restarts once; the chat field sits in that gap), and connecting a model with your own API key. Keys are kept in your Keychain and sent only to that provider.
Right-click the field → **Change Model…** to switch providers, or **Quit macobar**. The gap is there only while macobar runs: any quit removes it, and the next launch puts it back. After a force quit or crash, drag the empty spacers out of the Dock, or launch and quit macobar once.

## How it works
1. `Setup/` asks for permission and has `Dock/` add spacer tiles after Finder; `Dock/` then reads their on-screen frame through Accessibility.
2. `ChatBar/` pins a transparent panel with the text field exactly over that gap, and a reply sheet just above the Dock.
3. `ModelClient/` streams replies from the provider saved in `Providers/`.
4. `App/` wires the modules together.

## Modules
| Folder | Job |
|---|---|
| `Macobar/App` | Entry point and wiring; the only place concrete types meet |
| `Macobar/Dock` | Reserves the gap in the Dock and reports where it is |
| `Macobar/ChatBar` | The field in the Dock and the reply sheet above it |
| `Macobar/Setup` | The one-screen setup window and the Connect screen for choosing a model |
| `Macobar/Providers` | Model providers, their endpoints, and credentials in the Keychain |
| `Macobar/ModelClient` | Streams replies from the provider in its API format |
| `Macobar/Permissions` | Checks and requests Accessibility access |
| `Macobar/Brand` | Macie, the character shared by every screen |
| `MacobarTests` | Logic tests for pure code (no app launch) |
| `site` | The landing page: static HTML/CSS/JS, no build step |

Each folder has its own README. When a module changes, its README changes in the same edit.

## Code principles
- One type, one job; small files. Protocols only where a second implementation or a test needs one.
- Build only what the current milestone needs (YAGNI).
- Descriptive names, no `Manager`/`Helper`/`Utils`.
- A one-line `///` comment on every type, function and property; no comments that restate code.
- Swift 6 strict concurrency, value types by default, `private` by default, no force-unwraps.
