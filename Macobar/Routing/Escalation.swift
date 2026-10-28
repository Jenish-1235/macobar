import Foundation

/// When the fast model's attempt should be handed over to the main model, and what the main model is told.
enum Escalation {
    /// Failed tool calls after which the fast model is judged to be struggling.
    private static let toolErrorLimit = 2
    /// Phrases of a reply that refuses or gives up, lowercased with straight apostrophes.
    private static let refusals = [
        "i can't", "i cannot", "i can not", "i'm unable", "i am unable", "i'm not able", "i am not able",
        "i don't have access", "i do not have access", "as an ai",
    ]

    /// Why the main model should retry the prompt, or nil when the fast model's run stands.
    static func reason(toEscalate run: RunOutcome, expectedAction: Bool) -> String? {
        let answer = run.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !run.didFinish { return "The fast model didn't finish" }
        if run.userDeclined { return nil }
        if run.toolErrors >= toolErrorLimit { return "\(run.toolErrors) tool calls failed" }
        if expectedAction && run.toolCalls == 0 { return "It answered without acting" }
        if answer.isEmpty && run.toolCalls == 0 { return "It gave no answer" }
        if isRefusal(answer) { return "It declined or gave up" }
        return nil
    }

    /// `prompt` for the main model, noting what the fast model already did so it isn't done twice.
    static func handoverPrompt(for prompt: String, after run: RunOutcome) -> String {
        guard !run.completedActions.isEmpty else { return prompt }
        let done = run.completedActions.map { "- \($0)" }.joined(separator: "\n")
        return "\(prompt)\n\n(Another model already started on this and did:\n\(done)\nDon't repeat these; finish the rest.)"
    }

    /// Whether the start of `answer` refuses or gives up.
    private static func isRefusal(_ answer: String) -> Bool {
        let opening = answer.prefix(160).lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        return refusals.contains { opening.contains($0) }
    }
}
