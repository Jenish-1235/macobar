import Foundation
import Synchronization

/// Answers chat bar prompts with the active provider, remembering the conversation for follow-ups.
final class ModelResponder: ChatResponder {
    /// Who Macie is and how replies should read in the small card above the Dock.
    private static let instructions = """
        You are Macie, the assistant inside macobar, which lives in the user's macOS Dock. \
        Your replies appear in a small card above the Dock, so answer in a few short sentences of plain text, \
        without Markdown. You can't take actions on the Mac yet; if asked to, say briefly what you would do.
        """

    /// The finished turns, and the account they were had with.
    private struct Conversation {
        /// Account the turns were sent to; switching accounts starts over.
        var account: ProviderAccount?
        /// Completed turns; a turn is only kept once its reply finished.
        var turns: [ChatMessage] = []
    }

    /// Where the active provider and its key are saved.
    private let accountStore: ProviderAccountStore
    /// The conversation so far.
    private let conversation = Mutex(Conversation())

    /// Creates a responder that talks to whichever provider is active in `accountStore`.
    init(accountStore: ProviderAccountStore) {
        self.accountStore = accountStore
    }

    /// Streams the active model's reply to `prompt`, then remembers both for the next prompt.
    func reply(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (account, client) = try activeClient()
                    let question = ChatMessage(role: .user, text: prompt)
                    let earlierTurns = conversation.withLock { $0.account == account ? $0.turns : [] }
                    var answer = ""
                    for try await fragment in client.streamReply(instructions: Self.instructions, conversation: earlierTurns + [question]) {
                        answer += fragment
                        continuation.yield(fragment)
                    }
                    conversation.withLock { $0 = Conversation(account: account, turns: earlierTurns + [question, ChatMessage(role: .assistant, text: answer)]) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The active account and a client for it, read fresh so a newly connected model is used at once.
    private func activeClient() throws -> (ProviderAccount, ModelClient) {
        guard let account = accountStore.activeAccount else { throw ModelResponderError.notConnected }
        guard let credential = try accountStore.credential(for: account.kind) else { throw ModelResponderError.missingKey(account.kind) }
        return (account, try ModelClient(account: account, credential: credential))
    }
}

/// Why Macie can't reach a model.
enum ModelResponderError: LocalizedError {
    /// No provider has been connected.
    case notConnected
    /// The provider is saved but its key isn't in the Keychain.
    case missingKey(ProviderKind)

    /// What to tell the user.
    var errorDescription: String? {
        switch self {
        case .notConnected: "No model is connected. Right-click the field and choose Change Model…"
        case .missingKey(let kind): "Your \(kind.displayName) key is missing from the Keychain. Right-click the field and choose Change Model…"
        }
    }
}
