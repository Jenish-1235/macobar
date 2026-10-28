# Activity
A record of every action Macie takes, and undo for the file changes macobar can reverse on its own.

## Files
- `ActivityEntry.swift`: one action: id, date, tool name, the activity line from the reply card, outcome (`succeeded`, `failed`, `declined`), the start of its result (at most 300 characters), an optional `UndoStep`, and whether it was undone.
- `ActivityLog.swift`: the entries in `~/Library/Application Support/macobar/activity.json`, newest 500 kept: `entries()` (newest first), `append`, `markUndone(id:)`, `clear()`; atomic writes (tested).
- `UndoStep.swift`: the reversible effects: `moved(from:to:)`, `copied(to:)`, `wroteFile(path:)`, `createdFolder(path:)`, `trashed(original:trashURL:)`, and the pure `reversal` of each (tested).
- `Reversal.swift`: the file change that reverses a step: move back, put back from the Trash, trash, or trash a folder while it's empty.
- `UndoRunner.swift`: carries out a reversal with `FileManager`, refusing with `UndoError` when the files no longer match or a step would touch a protected location (tested).
- `UndoInference.swift`: `UndoStep.inferred(toolName:input:output:)`, the step for a successful `manage_file` call, read from its arguments and result; the path runs to the result's final full stop, since paths may hold line breaks (tested).
- `ActivityDay.swift`: entries grouped by calendar day for the window (tested).
- `HistoryModel.swift`, `HistoryView.swift`, `HistoryWindow.swift`: the charcoal History window: newest first, grouped by day, each row with time, activity and outcome, Undo on undoable rows, Clear History and Done.

## Public surface
- `ActivityLog(fileURL:capacity:)`, `ActivityEntry(toolName:activity:outcome:result:undoStep:date:)`
- `UndoStep.inferred(toolName:input:output:)`, `UndoRunner.undo(_:)`
- `HistoryModel(log:)`, `HistoryWindow(model:)`, `show()`

## What can be undone
| `manage_file` action | Undo |
|---|---|
| `move` | Moves it back; the final place comes from the result ("Moved to …"), so a move into a folder is handled |
| `copy` | Trashes the copy |
| `write_text` (new file) | Trashes the file; an overwrite can't be undone, since the old text is gone |
| `create_folder` | Trashes the folder, only while it's still empty; parent folders made with it stay |
| `trash` | Puts it back, when the result has a "Trash location: …" line |

Everything else (messages, events, app and system actions) is recorded but can't be undone. Undo never deletes: the inverse of making something is moving it to the Trash.

## Safety
- Undo refuses when the item or the folder it would go back to is gone, when something else now sits where it would go back to, or when a folder Macie made has things in it.
- Undo refuses any step that would touch a protected location, such as a system folder, `~/.ssh`, `~/Library/LaunchAgents` or macobar's own data (`UndoError.protected`, checked with `ProtectedLocations`).
- macOS may block taking an item out of the Trash (it's privacy-protected); the message then says to use Put Back in Finder.
- An undone entry is marked and loses its Undo; undoing the same change twice finds the files already moved and refuses.

## Gotchas
- The file is the shared state: the chat and scheduler agents, the tools and the window read it on every call. A lock serialises changes within the app.
- Entries are recorded by the agent after each tool call ends or is declined; MCP calls from other apps aren't recorded.
- Activity lines name files and apps, so the log stays on this Mac like Macie's memory; Clear History deletes the file.

## Tested by
`MacobarTests/ActivityTests.swift`; protected locations in `MacobarTests/DeviceSafetyTests.swift`.

## Depends on
Tools (`ToolInput`, `ProtectedLocations`), Setup (`SetupStyle`, `SetupButtonStyle`), Brand (`Macie`).
