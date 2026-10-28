# App
Entry point and wiring. The only module that knows every concrete type.

## Files
- `MacobarApp.swift`: `@main` entry that runs AppKit, plus the `AppDelegate` that starts the assembly and stops it on quit.
- `TerminationSignals.swift`: turns SIGTERM and SIGINT into a normal quit, so cleanup still runs.
- `AppAssembly.swift`: builds the modules, shows setup when needed, and feeds Dock geometry to the chat bar.
- `ModelResponder.swift`: the `ChatResponder` that answers as Macie with whichever provider is active, read fresh on every prompt. Keeps the conversation for follow-ups (a turn is kept only once its reply finishes) and starts over when the provider changes. A missing model or key shows as an error in the reply card, never as a silent fallback.

## Startup order
1. Restore the Dock gap if the user added macobar before.
2. Show the setup window if Accessibility access, the Dock gap or a connected model is missing; its step 3 opens the Connect sheet.
3. Wait for Accessibility access.
4. Replies always come from `ModelResponder`, so a model connected from setup or Change Model… is used from the next prompt.
5. Forward every `DockGeometry` update to `ChatBarController.follow(_:)`.

## Quitting
Every way out (Quit in the field's menu, closing setup early, logout, `kill`, Ctrl-C) goes through `applicationWillTerminate`, which removes the Dock gap.

## Depends on
Dock, ChatBar, Setup, Permissions, Providers, ModelClient.
