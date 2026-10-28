import Foundation
import Synchronization

/// Macie: answers prompts with the fast or main model, running tools it asks for until the task is done.
final class Agent: ChatResponder {
    /// Most model turns one prompt may take, so a confused loop can't run forever.
    private static let maxTurns = 30
    /// Longest tool output sent back to the model; every later step resends it, so it's kept modest.
    private static let maxToolOutput = 12_000
    /// Prompts remembered for follow-ups; older ones are dropped from the start to keep requests small.
    private static let rememberedPrompts = 8
    /// Times one model turn is retried after a rate limit.
    private static let rateLimitRetries = 3
    /// Longest rate-limit wait worth sitting through, in seconds.
    private static let longestRateLimitWait = 60.0

    /// What became of one tool call.
    private enum CallOutcome {
        /// It ran, doing what the activity says.
        case done(String)
        /// It failed or couldn't be run.
        case failed
        /// The user turned it down.
        case declined
    }

    /// The tools for one prompt, and what outside text has reached the model during it and before it.
    private struct PromptSession {
        /// Every tool available this prompt, by name.
        let tools: [String: any Tool]
        /// Tools as the model sees them, sorted so requests cache well.
        let definitions: [ToolDefinition]
        /// Outside text tools brought in during this prompt.
        var exposure = ContentExposure()
        /// Outside text still in the remembered conversation this attempt continues, which the model reads again.
        var earlierExposure = ContentExposure()
    }

    /// The finished items, and the account they were had with.
    private struct Conversation {
        /// Account the items were sent to; switching accounts starts over.
        var account: ProviderAccount?
        /// Completed exchanges; a prompt's items are only kept once it finished.
        var items: [ConversationItem] = []
        /// What outside text each remembered prompt brought in, oldest first, one per prompt in `items`.
        var exposures: [ContentExposure] = []
    }

    /// The account to use for a prompt and a client for it, read fresh each prompt.
    private let connect: @Sendable () throws -> (ProviderAccount, ModelClient)
    /// The fast model's account and a client for it, or nil when there is none; read fresh each prompt.
    private let connectFast: @Sendable () -> (ProviderAccount, ModelClient)?
    /// The built-in tools.
    private let tools: [any Tool]
    /// Tools fetched afresh for each prompt, such as those from connected MCP servers.
    private let promptTools: @Sendable () async -> [any Tool]
    /// Tools the user chose to always allow.
    private let approvals: ToolApprovals
    /// Where every action is recorded for the History window and undo; nil to keep no record (the bench).
    private let activityLog: ActivityLog?
    /// Whether finished prompts are kept for follow-ups; scheduled runs start fresh so one task's content can't steer the next.
    private let remembersConversation: Bool
    /// The conversation so far.
    private let conversation = Mutex(Conversation())

    /// Creates Macie with `tools` plus each prompt's `promptTools`, talking to the main and fast models saved in `accountStore`.
    convenience init(accountStore: ProviderAccountStore, tools: [any Tool], promptTools: @escaping @Sendable () async -> [any Tool] = { [] }, remembersConversation: Bool = true) {
        self.init(
            connect: { try Self.activeClient(in: accountStore) },
            connectFast: { Self.fastClient(in: accountStore) },
            tools: tools,
            promptTools: promptTools,
            remembersConversation: remembersConversation
        )
    }

    /// Creates Macie with `tools`, talking to the main model `connect` returns and, for simple prompts, the fast one `connectFast` returns.
    init(
        connect: @escaping @Sendable () throws -> (ProviderAccount, ModelClient),
        connectFast: @escaping @Sendable () -> (ProviderAccount, ModelClient)? = { nil },
        tools: [any Tool],
        promptTools: @escaping @Sendable () async -> [any Tool] = { [] },
        approvals: ToolApprovals = ToolApprovals(),
        activityLog: ActivityLog? = ActivityLog(),
        remembersConversation: Bool = true
    ) {
        self.connect = connect
        self.connectFast = connectFast
        self.tools = tools
        self.promptTools = promptTools
        self.approvals = approvals
        self.activityLog = activityLog
        self.remembersConversation = remembersConversation
    }

    /// Streams Macie's reply to `prompt`, running tools along the way, then remembers the exchange.
    func reply(to prompt: String) -> AsyncThrowingStream<ReplyEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(prompt, emit: { continuation.yield($0) })
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Sends `prompt` to the fast model when the router picks it, handing over to the main model when it struggles; a main model out of rate limit hands over to the fast one instead.
    private func run(_ prompt: String, emit: (ReplyEvent) -> Void) async throws {
        let (mainAccount, mainClient) = try connect()
        var session = await makeSession()
        guard let (fastAccount, fastClient) = connectFast(), fastAccount != mainAccount else {
            return try await finish(prompt, on: mainAccount, client: mainClient, session: &session, emit: emit)
        }
        guard PromptRouter.route(prompt, continuing: continuingTier(fast: fastAccount)).tier == .fast else {
            var outcome = RunOutcome(didFinish: false)
            do {
                return try await finish(prompt, on: mainAccount, client: mainClient, session: &session, recording: &outcome, emit: emit)
            } catch ModelClientError.rateLimited {
                emit(.activity("\(mainAccount.model) is rate-limited; using the fast model"))
                let handover = Escalation.handoverPrompt(for: prompt, after: outcome)
                return try await finish(handover, on: fastAccount, client: fastClient, session: &session, startsNewParagraph: !outcome.answer.isEmpty, emit: emit)
            }
        }
        emit(.activity("Using the fast model"))
        var outcome = RunOutcome(didFinish: false)
        do {
            try await attempt(prompt, on: fastAccount, client: fastClient, session: &session, recording: &outcome, emit: emit)
        } catch {
            try Task.checkCancellation()
        }
        guard Escalation.reason(toEscalate: outcome, expectedAction: PromptRouter.looksLikeCommand(prompt)) != nil else { return }
        emit(.activity("Handing over to \(mainAccount.model)"))
        let handover = Escalation.handoverPrompt(for: prompt, after: outcome)
        try await finish(handover, on: mainAccount, client: mainClient, session: &session, startsNewParagraph: !outcome.answer.isEmpty, emit: emit)
    }

    /// This prompt's tools: the built-in ones plus each prompt's extras, a built-in tool winning a name clash; extras' descriptions come from outside (MCP servers), so they count as outside text from the start.
    private func makeSession() async -> PromptSession {
        let builtInNames = Set(tools.map(\.name))
        let extras = (await promptTools()).filter { !builtInNames.contains($0.name) }
        let available = tools + extras
        return PromptSession(
            tools: Dictionary(available.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }),
            definitions: available.map(\.definition).sorted { $0.name < $1.name },
            exposure: ContentExposure(hasOutsideContent: !extras.isEmpty)
        )
    }

    /// Runs `prompt` to the end on `client`, failing when the model runs out of steps.
    private func finish(_ prompt: String, on account: ProviderAccount, client: ModelClient, session: inout PromptSession, startsNewParagraph: Bool = false, emit: (ReplyEvent) -> Void) async throws {
        var outcome = RunOutcome(didFinish: false)
        try await finish(prompt, on: account, client: client, session: &session, startsNewParagraph: startsNewParagraph, recording: &outcome, emit: emit)
    }

    /// Runs `prompt` to the end on `client`, failing when the model runs out of steps; `outcome` keeps what was done even if it fails midway.
    private func finish(_ prompt: String, on account: ProviderAccount, client: ModelClient, session: inout PromptSession, startsNewParagraph: Bool = false, recording outcome: inout RunOutcome, emit: (ReplyEvent) -> Void) async throws {
        try await attempt(prompt, on: account, client: client, session: &session, startsNewParagraph: startsNewParagraph, recording: &outcome, emit: emit)
        guard outcome.didFinish else {
            throw ModelClientError.failed("Macie stopped after \(Self.maxTurns) steps without finishing.")
        }
    }

    /// The loop: ask the model, run the tools it calls, send back results, until it answers without tools or runs out of steps; `outcome` keeps what was done even if the model fails midway.
    private func attempt(_ prompt: String, on account: ProviderAccount, client: ModelClient, session: inout PromptSession, startsNewParagraph: Bool = false, recording outcome: inout RunOutcome, emit: (ReplyEvent) -> Void) async throws {
        let (earlierItems, earlierExposures) = conversation.withLock { $0.account == account ? ($0.items, $0.exposures) : ([], []) }
        session.earlierExposure = earlierExposures.reduce(ContentExposure()) { $0.combined(with: $1) }
        var items = earlierItems + [.user(prompt)]
        for _ in 0..<Self.maxTurns {
            let turn = try await nextTurn(from: client, items: items, tools: session.definitions, startsNewParagraph: startsNewParagraph || !outcome.answer.isEmpty, emit: emit)
            outcome.answer += turn.text
            items.append(.assistant(turn))
            guard !turn.toolCalls.isEmpty else {
                let exposures = Array((earlierExposures + [session.exposure]).suffix(Self.rememberedPrompts))
                if remembersConversation {
                    conversation.withLock { $0 = Conversation(account: account, items: Self.recent(items), exposures: exposures) }
                }
                outcome.didFinish = true
                return
            }
            var results: [ToolResult] = []
            for call in turn.toolCalls {
                try Task.checkCancellation()
                let (result, callOutcome) = await perform(call, session: &session, emit: emit)
                outcome.toolCalls += 1
                switch callOutcome {
                case .done(let activity): outcome.completedActions.append(activity)
                case .failed: outcome.toolErrors += 1
                case .declined: outcome.userDeclined = true
                }
                results.append(result)
            }
            items.append(.toolResults(results))
        }
    }

    /// The model that answered the remembered conversation, so a follow-up can stay with it.
    private func continuingTier(fast: ProviderAccount) -> ModelTier? {
        conversation.withLock { saved in
            guard let account = saved.account, !saved.items.isEmpty else { return nil }
            return account == fast ? .fast : .strong
        }
    }

    /// Streams one model turn, waiting out short rate limits (shown in the card) and retrying.
    private func nextTurn(from client: ModelClient, items: [ConversationItem], tools: [ToolDefinition], startsNewParagraph: Bool, emit: (ReplyEvent) -> Void) async throws -> AssistantTurn {
        var retries = 0
        while true {
            do {
                var turn = AssistantTurn()
                var needsBreak = startsNewParagraph
                for try await event in client.streamReply(instructions: MacieInstructions.current(), conversation: items, tools: tools) {
                    switch event {
                    case .text(let text):
                        emit(.text(needsBreak ? "\n\n" + text : text))
                        needsBreak = false
                    case .finished(let finished):
                        turn = finished
                    }
                }
                return turn
            } catch ModelClientError.rateLimited(let message, let retryAfter) {
                let wait = retryAfter ?? Double(10 * (retries + 1))
                guard retries < Self.rateLimitRetries, wait <= Self.longestRateLimitWait else {
                    throw ModelClientError.rateLimited(message: message, retryAfter: retryAfter)
                }
                retries += 1
                emit(.activity("Waiting \(Int(wait.rounded(.up)))s for the rate limit"))
                try await Task.sleep(for: .seconds(max(wait, 1)))
            }
        }
    }

    /// Runs one tool call, asking first when its risk calls for it, records it, and says what became of it; failures go back to the model as error results.
    private func perform(_ call: ToolCall, session: inout PromptSession, emit: (ReplyEvent) -> Void) async -> (result: ToolResult, outcome: CallOutcome) {
        guard let tool = session.tools[call.name] else {
            return (ToolResult(callID: call.id, output: "There is no tool named \(call.name).", isError: true), .failed)
        }
        guard let arguments = (try? JSONValue.parse(call.arguments))?.object else {
            return (ToolResult(callID: call.id, output: JSONValue.object(["INVALID_JSON": .string(call.arguments)]).jsonString, isError: true), .failed)
        }
        let input = ToolInput(arguments)
        let activity = tool.activity(for: input)
        let risk = tool.risk(for: input)
        let sendsDataOut = ToolCatalog.sendsDataOut.contains(tool.name)
        let exposure = session.exposure.combined(with: session.earlierExposure)
        guard await isAllowed(tool, risk: risk, sendsDataOut: sendsDataOut, activity: activity, exposure: exposure, emit: emit) else {
            record(tool, activity: activity, outcome: .declined)
            return (ToolResult(callID: call.id, output: "The user declined: \(activity). Don't retry it; ask what they'd like instead.", isError: true), .declined)
        }
        emit(.activity(activity))
        session.exposure = session.exposure.adding(readsOutsideContent: tool.readsOutsideContent(for: input), sendsDataOut: sendsDataOut, risk: risk)
        do {
            let output: (text: String, images: [ToolImage]) = if let visual = tool as? any VisualTool {
                try await visual.look(input)
            } else {
                (try await tool.run(input), [])
            }
            record(tool, activity: activity, outcome: .succeeded, result: output.text, undoStep: UndoStep.inferred(toolName: tool.name, input: input, output: output.text))
            return (ToolResult(callID: call.id, output: Self.trimmed(output.text.isEmpty ? "Done." : output.text), isError: false, images: output.images), .done(activity))
        } catch {
            record(tool, activity: activity, outcome: .failed, result: error.localizedDescription)
            return (ToolResult(callID: call.id, output: Self.trimmed(error.localizedDescription), isError: true), .failed)
        }
    }

    /// Adds the action to the activity log; a log that can't be written never stops the task.
    private func record(_ tool: any Tool, activity: String, outcome: ActivityEntry.Outcome, result: String = "", undoStep: UndoStep? = nil) {
        try? activityLog?.append(ActivityEntry(toolName: tool.name, activity: activity, outcome: outcome, result: result, undoStep: undoStep))
    }

    /// Whether the user allows `tool` to run at `risk`, asking in the reply card when needed; Always Allow doesn't count once outside content is in the conversation, and sending data off the Mac asks once private text is, so a page or file can't steer Macie into an unasked action or leak.
    private func isAllowed(_ tool: any Tool, risk: ToolRisk, sendsDataOut: Bool, activity: String, exposure: ContentExposure, emit: (ReplyEvent) -> Void) async -> Bool {
        let alwaysAllowed = risk == .confirmOnce && approvals.isAlwaysAllowed(tool.name)
        if exposure.runsWithoutAsking(risk: risk, isAlwaysAllowed: alwaysAllowed, sendsDataOut: sendsDataOut) { return true }
        let reason: String? = if alwaysAllowed {
            "Asking again because Macie read a page, file or screen in this conversation."
        } else if risk == .none {
            "Asking because this reaches the internet after Macie read your files, screen or messages in this conversation."
        } else {
            nil
        }
        let request = ApprovalRequest(action: activity, canAlwaysAllow: risk == .confirmOnce, reason: reason)
        emit(.approval(request))
        let decision = await withTaskCancellationHandler {
            await request.decision()
        } onCancel: {
            request.decide(.deny)
        }
        if decision == .alwaysAllow, risk == .confirmOnce { approvals.alwaysAllow(tool.name) }
        return decision != .deny
    }

    /// The active account and a client for it, read fresh so a newly connected model is used at once.
    private static func activeClient(in accountStore: ProviderAccountStore) throws -> (ProviderAccount, ModelClient) {
        guard let account = accountStore.activeAccount else { throw AgentError.notConnected }
        guard let credential = try accountStore.credential(for: account.kind) else { throw AgentError.missingKey(account.kind) }
        return (account, try ModelClient(account: account, credential: credential))
    }

    /// The fast account and a client for it, or nil when none is set or its key is missing.
    private static func fastClient(in accountStore: ProviderAccountStore) -> (ProviderAccount, ModelClient)? {
        guard let account = accountStore.fastAccount, let credential = (try? accountStore.credential(for: account.kind)) ?? nil else { return nil }
        return try? (account, ModelClient(account: account, credential: credential))
    }

    /// `items` without the oldest prompts beyond `rememberedPrompts`, cut at a prompt so every turn keeps its context.
    private static func recent(_ items: [ConversationItem]) -> [ConversationItem] {
        let promptStarts = items.indices.filter { if case .user = items[$0] { true } else { false } }
        guard promptStarts.count > rememberedPrompts else { return items }
        return Array(items[promptStarts[promptStarts.count - rememberedPrompts]...])
    }

    /// `output` cut to the length sent to the model.
    private static func trimmed(_ output: String) -> String {
        output.count <= maxToolOutput ? output : String(output.prefix(maxToolOutput)) + "\n[Output truncated]"
    }
}

/// Why Macie can't reach a model.
enum AgentError: LocalizedError {
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
