# App
Entry point and wiring. The only module that knows every concrete type.

## Files
- `MacobarApp.swift`: `@main` entry that runs AppKit, plus the `AppDelegate` that starts the assembly.
- `AppAssembly.swift`: builds the modules, asks for permission, reserves the gap, and feeds Dock geometry to the chat bar.
- `PlaceholderResponder.swift`: temporary `ChatResponder` that streams a fixed note. Replaced by the agent in milestone 2.

## Startup order
1. Wait for Accessibility permission.
2. Reserve the Dock gap (restarts the Dock only if the gap changed).
3. Forward every `DockGeometry` update to `ChatBarController.follow(_:)`.

## Depends on
Dock, ChatBar, Permissions.
