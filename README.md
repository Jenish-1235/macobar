# macobar

A persistent agent for macOS that you talk to from a text field living inside the Dock.

## Build and run
Requires Xcode 27+, macOS 26+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make run    # generate the project, build, and launch
make test   # run the logic tests
```

On first launch a setup window walks through two steps: allowing **Accessibility** access (macobar needs it to read where the Dock is), and adding an empty gap right after Finder, which restarts the Dock once. The chat field sits in that gap.
Right-click the field → **Quit macobar** to remove the gap and quit. If macobar is deleted without quitting, drag the empty spacers out of the Dock.

## How it works
1. `Setup/` asks for permission and has `Dock/` add spacer tiles after Finder; `Dock/` then reads their on-screen frame through Accessibility.
2. `ChatBar/` pins a transparent panel with the text field exactly over that gap, and a reply sheet just above the Dock.
3. `App/` wires the modules together. Replies come from a placeholder until the agent lands.

## Modules
| Folder | Job |
|---|---|
| `Macobar/App` | Entry point and wiring; the only place concrete types meet |
| `Macobar/Dock` | Reserves the gap in the Dock and reports where it is |
| `Macobar/ChatBar` | The field in the Dock and the reply sheet above it |
| `Macobar/Setup` | The one-screen setup window (Accessibility + Dock gap) |
| `Macobar/Permissions` | Checks and requests Accessibility access |
| `Macobar/Brand` | The macobar mark, shared by every screen |
| `MacobarTests` | Logic tests for pure code (no app launch) |

Each folder has its own README. When a module changes, its README changes in the same edit.

## Code principles
- One type, one job; small files. Protocols only where a second implementation or a test needs one.
- Build only what the current milestone needs (YAGNI).
- Descriptive names, no `Manager`/`Helper`/`Utils`.
- A one-line `///` comment on every type, function and property; no comments that restate code.
- Swift 6 strict concurrency, value types by default, `private` by default, no force-unwraps.
