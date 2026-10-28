import Foundation

/// Reverses the newest file change Macie made that can still be undone.
struct UndoLastActionTool: Tool {
    /// Name the model calls it by.
    let name = "undo_last_action"
    /// When to call it and what it returns.
    let description = """
        Undoes your latest undoable file change (move, rename, copy, new folder or file, trash) when the user says undo, \
        put it back, or your last change was a mistake. Messages, events, app actions and overwrites can't be undone.
        """

    /// Takes no arguments.
    var parameters: JSONValue { Schema.object() }

    /// Undoing changes files again, so it asks first.
    func risk(for input: ToolInput) -> ToolRisk { .confirmOnce }

    /// Names the action being undone, so the approval says what will change.
    func activity(for input: ToolInput) -> String {
        guard let entry = try? ActivityLog().entries().first(where: \.isUndoable) else { return "Undoing the last file change" }
        return "Undoing: \(entry.activity)"
    }

    /// Reverses the newest undoable entry and marks it undone.
    func run(_ input: ToolInput) async throws -> String {
        let log = ActivityLog()
        guard let entry = try log.entries().first(where: \.isUndoable), let step = entry.undoStep else {
            throw ToolError("Nothing can be undone. Only file changes you made (move, copy, new folder, new file, trash) can be; tell the user.")
        }
        let done = try UndoRunner.undo(step)
        try log.markUndone(id: entry.id)
        return "Undid “\(entry.activity)”. \(done)"
    }
}

/// Lists the last actions Macie took.
struct RecentActivityTool: Tool {
    /// Most entries listed.
    private static let entryLimit = 20

    /// Name the model calls it by.
    let name = "recent_activity"
    /// When to call it and what it returns.
    let description = """
        Lists your last 20 tool actions with outcome and undoability. Call it when the user asks what you did or whether \
        it worked, or to check what undo_last_action would reverse.
        """

    /// Takes no arguments.
    var parameters: JSONValue { Schema.object() }

    /// Its result repeats earlier actions and errors, which can quote pages, files and screens.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Describes the lookup.
    func activity(for input: ToolInput) -> String { "Checking recent activity" }

    /// One line per entry, newest first.
    func run(_ input: ToolInput) async throws -> String {
        let entries = try ActivityLog().entries().prefix(Self.entryLimit)
        guard !entries.isEmpty else { return "No actions recorded yet." }
        return entries.map { entry in
            "\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(entry.activity) · \(Self.status(of: entry))"
        }.joined(separator: "\n")
    }

    /// How `entry` ended, and whether it can be undone.
    private static func status(of entry: ActivityEntry) -> String {
        if entry.isUndone { return "undone" }
        switch entry.outcome {
        case .succeeded: return entry.isUndoable ? "done (can be undone)" : "done"
        case .failed: return "failed: \(entry.result.replacingOccurrences(of: "\n", with: " "))"
        case .declined: return "declined by the user"
        }
    }
}
