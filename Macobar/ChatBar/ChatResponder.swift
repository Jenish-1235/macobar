import Foundation
import Synchronization

/// Anything that can answer a prompt typed into the chat bar, streaming what it says and does.
protocol ChatResponder: Sendable {
    /// Streams the reply to `prompt`: text, actions taken, and requests for approval.
    func reply(to prompt: String) -> AsyncThrowingStream<ReplyEvent, Error>
}

/// One thing that happened while replying.
enum ReplyEvent: Sendable {
    /// More reply text.
    case text(String)
    /// An action being taken, e.g. "Opening Safari".
    case activity(String)
    /// An action waiting for the user's go-ahead.
    case approval(ApprovalRequest)
}

/// The user's answer to an approval request.
enum ApprovalDecision: Sendable {
    /// Run it this time.
    case allow
    /// Run it, and don't ask again for this kind of action.
    case alwaysAllow
    /// Don't run it.
    case deny
}

/// An action paused until the user allows or denies it in the reply card.
final class ApprovalRequest: Sendable, Identifiable, Equatable {
    /// Where the request stands.
    private enum State {
        /// Waiting; holds the paused caller once it starts waiting.
        case pending(CheckedContinuation<ApprovalDecision, Never>?)
        /// Answered.
        case decided(ApprovalDecision)
    }

    /// Distinguishes requests in the UI.
    let id = UUID()
    /// What will happen, e.g. "Quit Safari".
    let action: String
    /// Whether "Always allow" is offered.
    let canAlwaysAllow: Bool
    /// Why Macie is asking, when it isn't the usual reason (e.g. she read outside content after the user chose Always Allow).
    let reason: String?
    /// The answer, or the caller waiting for it.
    private let state = Mutex(State.pending(nil))

    /// Creates a request for `action`.
    init(action: String, canAlwaysAllow: Bool, reason: String? = nil) {
        self.action = action
        self.canAlwaysAllow = canAlwaysAllow
        self.reason = reason
    }

    /// Waits for the user's answer.
    func decision() async -> ApprovalDecision {
        await withCheckedContinuation { continuation in
            let earlierDecision: ApprovalDecision? = state.withLock { state in
                if case .decided(let decision) = state { return decision }
                state = .pending(continuation)
                return nil
            }
            if let earlierDecision { continuation.resume(returning: earlierDecision) }
        }
    }

    /// Records the user's answer and resumes the waiting caller; later answers are ignored.
    func decide(_ decision: ApprovalDecision) {
        let waiting: CheckedContinuation<ApprovalDecision, Never>? = state.withLock { state in
            guard case .pending(let continuation) = state else { return nil }
            state = .decided(decision)
            return continuation
        }
        waiting?.resume(returning: decision)
    }

    /// Requests are equal when they're the same request.
    static func == (lhs: ApprovalRequest, rhs: ApprovalRequest) -> Bool { lhs.id == rhs.id }
}
