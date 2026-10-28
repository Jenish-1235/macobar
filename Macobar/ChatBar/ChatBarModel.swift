import Observation

/// State behind the chat bar: what's being typed, the current prompt with what Macie said and did, and actions other AI apps want approved.
@MainActor
@Observable
final class ChatBarModel {
    /// One prompt and the reply it has produced so far.
    struct Exchange: Equatable {
        /// What the user asked.
        let prompt: String
        /// Reply text received so far.
        var reply = ""
        /// Actions taken so far, e.g. "Opening Safari".
        var activities: [String] = []
        /// An action waiting for the user's go-ahead.
        var pendingApproval: ApprovalRequest?
        /// Whether reply fragments are still arriving.
        var isResponding = true
        /// What went wrong, when the reply failed.
        var failureMessage: String?
    }

    /// An action another AI app wants to run with Macie's tools, waiting for the user's answer.
    struct ExternalApproval: Equatable {
        /// The app asking, e.g. "Claude Code".
        let requester: String
        /// The action and its answer.
        let request: ApprovalRequest
    }

    /// Text currently in the field; typing or talking silences a reply being read aloud.
    var draft = "" { didSet { if !draft.isEmpty { spokenReply?.stop() } } }
    /// Bumped to ask the field for keyboard focus.
    var fieldFocusRequests = 0
    /// Whether the user is talking to Macie with Option-Space held.
    var isHearingVoice = false
    /// The current exchange, or nil when collapsed.
    private(set) var exchange: Exchange?
    /// The exchange to show in the card: only once it needs the user, with an approval or the finished reply; work in progress stays out of sight.
    var shownExchange: Exchange? {
        guard let exchange, !exchange.isResponding || exchange.pendingApproval != nil else { return nil }
        return exchange
    }
    /// What Macie is doing while she works out of sight, e.g. "Opening Safari…", shown in the empty field; nil otherwise.
    var workingStatus: String? {
        guard let exchange, exchange.isResponding, exchange.pendingApproval == nil else { return nil }
        return "\(exchange.activities.last ?? "Thinking")…"
    }
    /// Approvals other apps are waiting on, oldest first.
    private(set) var externalApprovals: [ExternalApproval] = []
    /// The approval another app is waiting on to show now: the oldest, once no reply is in progress.
    var shownExternalApproval: ExternalApproval? {
        exchange?.isResponding == true ? nil : externalApprovals.first
    }
    /// Whether replies are read aloud, chosen in the field's menu.
    var speaksReplies: Bool {
        get { spokenReply?.isOn ?? false }
        set { spokenReply?.isOn = newValue }
    }
    /// Where replies come from.
    @ObservationIgnored private let responder: ChatResponder
    /// Reads replies aloud when the user turned that on; nil keeps the model silent (tests).
    @ObservationIgnored private let spokenReply: SpokenReply?
    /// The reply in progress, cancelled when a new prompt replaces it.
    @ObservationIgnored private var replyTask: Task<Void, Never>?

    /// Creates a model that sends prompts to `responder`, reading replies aloud through `spokenReply` when it's on.
    init(responder: ChatResponder, spokenReply: SpokenReply? = nil) {
        self.responder = responder
        self.spokenReply = spokenReply
    }

    /// Sends the draft and streams the reply into `exchange`.
    func submit() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        draft = ""
        replyTask?.cancel()
        spokenReply?.begin()
        exchange = Exchange(prompt: prompt)
        replyTask = Task { await streamReply(to: prompt) }
    }

    /// Queues `request` from `requester` (e.g. "Claude Code") behind any reply in progress, and returns the user's answer.
    func requestApproval(_ request: ApprovalRequest, from requester: String) async -> ApprovalDecision {
        externalApprovals.append(ExternalApproval(requester: requester, request: request))
        let decision = await request.decision()
        externalApprovals.removeAll { $0.request == request }
        return decision
    }

    /// Silences a reply being read aloud, e.g. when the user starts talking.
    func stopSpeaking() {
        spokenReply?.stop()
    }

    /// Answers the pending approval request.
    func decide(_ decision: ApprovalDecision) {
        exchange?.pendingApproval?.decide(decision)
        exchange?.pendingApproval = nil
    }

    /// Shows a short notice in the reply card, e.g. why voice input stopped, without touching the draft.
    func showNotice(_ message: String) {
        replyTask?.cancel()
        exchange = Exchange(prompt: "Macie", isResponding: false, failureMessage: message)
    }

    /// Denies the shown approval another app is waiting on; otherwise collapses the reply and stops any reply in progress.
    func dismiss() {
        if let approval = shownExternalApproval { return approval.request.decide(.deny) }
        replyTask?.cancel()
        spokenReply?.stop()
        exchange = nil
    }

    /// Collapses the reply only if it has finished, so work in progress and other apps' approvals stay visible.
    func dismissIfFinished() {
        guard exchange?.isResponding != true else { return }
        spokenReply?.stop()
        exchange = nil
    }

    /// Applies events as they arrive, then records how the reply ended.
    private func streamReply(to prompt: String) async {
        do {
            for try await event in responder.reply(to: prompt) {
                guard !Task.isCancelled else { return }
                switch event {
                case .text(let text):
                    exchange?.reply += text
                    spokenReply?.append(text)
                case .activity(let activity): exchange?.activities.append(activity)
                case .approval(let request): exchange?.pendingApproval = request
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            exchange?.failureMessage = "The reply stopped: \(error.localizedDescription)"
        }
        guard !Task.isCancelled else { return }
        spokenReply?.finish()
        exchange?.isResponding = false
    }
}
