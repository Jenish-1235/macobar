/// How one model's attempt at a prompt went, as the escalation rule needs it.
struct RunOutcome: Sendable, Equatable {
    /// Tool calls the model made.
    var toolCalls = 0
    /// Of those, the ones that failed.
    var toolErrors = 0
    /// Whether the user turned down one of its actions; the main model would only ask again.
    var userDeclined = false
    /// Everything the model said.
    var answer = ""
    /// Whether it reached an answer; false when it ran out of steps or the model failed.
    var didFinish = true
    /// What it did successfully, e.g. "Opening Safari", so a second model doesn't repeat it.
    var completedActions: [String] = []
}
