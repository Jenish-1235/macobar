import Foundation
import Observation

/// State behind the History window: the log grouped by day, undoing entries, and clearing it.
@MainActor
@Observable
final class HistoryModel {
    /// The log, newest day first.
    private(set) var days: [ActivityDay] = []
    /// Why the last read, undo or clear failed, if it did.
    private(set) var failure: String?
    /// Where the entries are kept.
    @ObservationIgnored private let log: ActivityLog

    /// Shows the entries in `log`; nothing is read until `reload()`.
    init(log: ActivityLog = ActivityLog()) {
        self.log = log
    }

    /// Reads the log again and drops any old failure, so the window opens on what's true now.
    func reload() {
        failure = nil
        readLog()
    }

    /// Reverses `entry`'s file change and marks it undone, or says why it can't.
    func undo(_ entry: ActivityEntry) {
        guard let step = entry.undoStep else { return }
        failure = nil
        do {
            _ = try UndoRunner.undo(step)
            try log.markUndone(id: entry.id)
        } catch {
            failure = error.localizedDescription
        }
        readLog()
    }

    /// Forgets every entry; files are left as they are.
    func clear() {
        failure = nil
        do {
            try log.clear()
        } catch {
            failure = "Couldn't clear the history: \(error.localizedDescription)"
        }
        readLog()
    }

    /// Groups the log's entries into `days`, or says why the log can't be read.
    private func readLog() {
        do {
            days = ActivityDay.grouping(try log.entries())
        } catch {
            failure = "Couldn't read the history: \(error.localizedDescription) Clear History starts a new one."
        }
    }
}
