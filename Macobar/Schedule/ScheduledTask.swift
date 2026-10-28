import Foundation

/// A prompt Macie runs on her own at a set time, once or on repeat.
struct ScheduledTask: Codable, Sendable, Equatable {
    /// Short stable name the model refers to it by, e.g. "t3".
    let id: String
    /// What to ask Macie; written to stand alone, since it runs without the chat's conversation.
    let prompt: String
    /// When it runs next.
    var nextRun: Date
    /// How often it runs again.
    let repeatRule: RepeatRule
    /// What Macie answered last time, shortened.
    var lastResult: String?
    /// When it last ran.
    var lastRun: Date?
}
