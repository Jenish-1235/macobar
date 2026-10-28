/// How waiting for the user ended.
enum WaitOutcome: Equatable, Sendable {
    /// The user did it; says what happened, e.g. "Opened the File menu".
    case matched(String)
    /// The timeout passed first.
    case timedOut
    /// The wait was cancelled, e.g. the user dismissed the reply.
    case cancelled
}
