import Foundation

/// One action Macie took or was refused, as kept in the activity log.
struct ActivityEntry: Codable, Sendable, Equatable, Identifiable {
    /// Longest result kept, in characters.
    static let resultLength = 300

    /// How an action ended.
    enum Outcome: String, Codable, Sendable {
        /// It ran and finished.
        case succeeded
        /// It ran and failed.
        case failed
        /// The user said no, so it never ran.
        case declined
    }

    /// Stable identity, for undoing and listing.
    let id: UUID
    /// When it ended.
    let date: Date
    /// The tool that ran, e.g. "manage_file".
    let toolName: String
    /// What it did, as shown in the reply card, e.g. "Creating folder “Invoices”".
    let activity: String
    /// How it ended.
    let outcome: Outcome
    /// The start of the tool's result or error.
    let result: String
    /// How to reverse it, when macobar can.
    let undoStep: UndoStep?
    /// Whether it has been undone.
    var isUndone: Bool

    /// Records `activity` by `toolName` ending with `outcome` and `result` (cut to `resultLength`), reversible by `undoStep`.
    init(toolName: String, activity: String, outcome: Outcome, result: String = "", undoStep: UndoStep? = nil, date: Date = .now) {
        id = UUID()
        self.date = date
        self.toolName = toolName
        self.activity = activity
        self.outcome = outcome
        self.result = String(result.prefix(Self.resultLength))
        self.undoStep = undoStep
        isUndone = false
    }

    /// Whether it can still be undone.
    var isUndoable: Bool { undoStep != nil && !isUndone }
}
