# App
Entry point and wiring. The only module that knows every concrete type.

## Files
- `MacobarApp.swift`: `@main` entry that runs AppKit, plus the `AppDelegate` that starts the assembly.
- `AppAssembly.swift`: builds the modules, shows setup when needed, and feeds Dock geometry to the chat bar.
- `PlaceholderResponder.swift`: temporary `ChatResponder` that streams a fixed note. Replaced by the agent in milestone 2.

## Startup order
1. Show the setup window if Accessibility access or the Dock gap is missing.
2. Wait for Accessibility access.
3. Forward every `DockGeometry` update to `ChatBarController.follow(_:)`.

## Depends on
Dock, ChatBar, Setup, Permissions.
