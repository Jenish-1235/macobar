import Observation

/// State behind the chat bar: what's being typed and the current prompt and reply.
@MainActor
@Observable
final class ChatBarModel {
    /// One prompt and the reply it has produced so far.
    struct Exchange: Equatable {
        /// What the user asked.
        let prompt: String
        /// Reply text received so far.
        var reply = ""
        /// Whether reply fragments are still arriving.
        var isResponding = true
        /// What went wrong, when the reply failed.
        var failureMessage: String?
    }

    /// Text currently in the field.
    var draft = ""
    /// The exchange shown above the Dock, or nil when collapsed.
    private(set) var exchange: Exchange?
    /// Where replies come from.
    @ObservationIgnored private let responder: ChatResponder
    /// The reply in progress, cancelled when a new prompt replaces it.
    @ObservationIgnored private var replyTask: Task<Void, Never>?

    /// Creates a model that sends prompts to `responder`.
    init(responder: ChatResponder) {
        self.responder = responder
    }

    /// Sends the draft and streams the reply into `exchange`.
    func submit() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        draft = ""
        replyTask?.cancel()
        exchange = Exchange(prompt: prompt)
        replyTask = Task { await streamReply(to: prompt) }
    }

    /// Collapses the reply and stops any reply in progress.
    func dismiss() {
        replyTask?.cancel()
        exchange = nil
    }

    /// Collapses the reply only if it has finished, so work in progress stays visible.
    func dismissIfFinished() {
        guard exchange?.isResponding != true else { return }
        dismiss()
    }

    /// Appends fragments as they arrive, then records how the reply ended.
    private func streamReply(to prompt: String) async {
        do {
            for try await fragment in responder.reply(to: prompt) {
                guard !Task.isCancelled else { return }
                exchange?.reply += fragment
            }
        } catch {
            guard !Task.isCancelled else { return }
            exchange?.failureMessage = "The reply stopped: \(error.localizedDescription)"
        }
        guard !Task.isCancelled else { return }
        exchange?.isResponding = false
    }
}
