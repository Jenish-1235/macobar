import Foundation
import Testing

/// A tool that echoes its "text" argument at a fixed risk.
private struct EchoTool: Tool {
    /// Name the model calls it by.
    var name = "echo"
    /// How much confirmation every call needs.
    var fixedRisk = ToolRisk.none
    /// When to call it and what it returns.
    let description = "Echoes text."

    /// Takes the text to echo.
    var parameters: JSONValue { Schema.object(["text": Schema.string("Text to echo.")], required: ["text"]) }

    /// The fixed risk.
    func risk(for input: ToolInput) -> ToolRisk { fixedRisk }

    /// Describes the echo.
    func activity(for input: ToolInput) -> String { "Echoing" }

    /// Returns the text, or fails when it's missing.
    func run(_ input: ToolInput) async throws -> String { try input.requiredString("text") }
}

/// A tool that reads freely and asks once to write, like the clipboard: "write" as its text makes the call a write.
private struct ReadWriteTool: Tool {
    /// Name the model calls it by.
    let name = "read_write"
    /// When to call it and what it returns.
    let description = "Reads, or writes when the text is \"write\"."

    /// Takes the text.
    var parameters: JSONValue { Schema.object(["text": Schema.string("\"write\" to write.")], required: ["text"]) }

    /// Writing asks once; reading doesn't.
    func risk(for input: ToolInput) -> ToolRisk { input.string("text") == "write" ? .confirmOnce : .none }

    /// Names the action.
    func activity(for input: ToolInput) -> String { input.string("text") == "write" ? "Writing" : "Reading" }

    /// Returns the text.
    func run(_ input: ToolInput) async throws -> String { try input.requiredString("text") }
}

/// Stands in for the Dock: records each approval asked for and gives a fixed answer.
private actor FakeApprover {
    /// One approval asked for.
    struct Ask: Equatable {
        /// The app named in the prompt.
        let appName: String
        /// The action shown.
        let action: String
        /// Whether Always Allow was offered.
        let canAlwaysAllow: Bool
        /// Why the prompt says it's asking, if not the usual reason.
        var reason: String? = nil
    }

    /// The answer to every request.
    private let answer: ApprovalDecision
    /// Approvals asked for, in order.
    private(set) var asks: [Ask] = []

    /// Answers every request with `answer`.
    init(answer: ApprovalDecision) {
        self.answer = answer
    }

    /// Records `request` from `appName` and answers it.
    func decide(_ request: ApprovalRequest, from appName: String) -> ApprovalDecision {
        asks.append(Ask(appName: appName, action: request.action, canAlwaysAllow: request.canAlwaysAllow, reason: request.reason))
        return answer
    }
}

/// Verifies when AI apps' tool calls ask the user in the Dock; serialized because one test checks that nothing is saved in shared preferences.
@Suite(.serialized)
struct MCPApprovalPolicyTests {
    /// A handler sharing `tools` whose approvals go to `approver`.
    private func handler(_ tools: [any Tool], approver: FakeApprover) -> MCPRequestHandler {
        MCPRequestHandler(tools: tools, version: "1", approver: { request, appName in await approver.decide(request, from: appName) })
    }

    /// The decoded result of calling `tool` with `text` through `handler` in `session`.
    private func call(_ tool: String, text: String = "hi", on handler: MCPRequestHandler, session: String = "s1") async throws -> JSONValue? {
        let body = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(tool)","arguments":{"text":"\#(text)"}}}"#
        guard let data = await handler.response(to: Data(body.utf8), sessionID: session) else { return nil }
        return try JSONDecoder().decode(JSONValue.self, from: data)["result"]
    }

    /// A tool name no earlier run has always-allowed, since Always Allow is kept in preferences.
    private static func freshToolName() -> String {
        "test_\(UUID().uuidString.prefix(8).lowercased())"
    }

    @Test("A harmless risk-free tool runs without asking")
    func silentTool() async throws {
        let approver = FakeApprover(answer: .deny)
        let result = try await call("system_status", on: handler([EchoTool(name: "system_status")], approver: approver))
        #expect(result == ["content": [["type": "text", "text": "hi"]], "isError": false])
        #expect(await approver.asks.isEmpty)
    }

    @Test("A risk-free tool that could read private data asks first, and Always Allow covers only that app's session")
    func privateReadAsksPerSession() async throws {
        let approver = FakeApprover(answer: .alwaysAllow)
        let handler = handler([EchoTool(name: "read_file")], approver: approver)
        #expect(try await call("read_file", on: handler, session: "s1")?["isError"] == false)
        #expect(try await call("read_file", on: handler, session: "s1")?["isError"] == false)
        #expect(try await call("read_file", on: handler, session: "s2")?["isError"] == false)
        let ask = FakeApprover.Ask(appName: MCPRequestHandler.unnamedApp, action: "Echoing", canAlwaysAllow: true, reason: MCPRequestHandler.sessionGrantReason)
        #expect(await approver.asks == [ask, ask])
    }

    @Test("Always Allow for a tool's harmless use doesn't cover its riskier use in the same session")
    func alwaysAllowKeepsItsRisk() async throws {
        let approver = FakeApprover(answer: .alwaysAllow)
        let handler = handler([ReadWriteTool()], approver: approver)
        _ = try await call("read_write", text: "read", on: handler)
        _ = try await call("read_write", text: "write", on: handler)
        _ = try await call("read_write", text: "read", on: handler)
        _ = try await call("read_write", text: "write", on: handler)
        #expect(await approver.asks.map(\.action) == ["Reading", "Writing"])
    }

    @Test("A timer asks first, since its notification would show the app's text as Macie's")
    func timerAsks() async throws {
        let approver = FakeApprover(answer: .allow)
        _ = try await call("set_timer", on: handler([EchoTool(name: "set_timer")], approver: approver))
        #expect(await approver.asks.count == 1)
    }

    @Test("A risk-free tool that could read private data is declined when the user denies it")
    func privateReadDenied() async throws {
        let approver = FakeApprover(answer: .deny)
        let result = try await call("read_file", on: handler([EchoTool(name: "read_file")], approver: approver))
        #expect(result?["isError"] == true)
    }

    @Test("Allowing in the Dock runs a tool that asks every time, without offering Always Allow")
    func allow() async throws {
        let approver = FakeApprover(answer: .allow)
        let result = try await call("send", on: handler([EchoTool(name: "send", fixedRisk: .confirmEveryTime)], approver: approver))
        #expect(result?["isError"] == false)
        #expect(await approver.asks == [.init(appName: MCPRequestHandler.unnamedApp, action: "Echoing", canAlwaysAllow: false)])
    }

    @Test("Denying in the Dock tells the app the user declined")
    func deny() async throws {
        let approver = FakeApprover(answer: .deny)
        let result = try await call("send", on: handler([EchoTool(name: "send", fixedRisk: .confirmEveryTime)], approver: approver))
        #expect(result?["isError"] == true)
        #expect(result?["content"]?.array?.first?["text"] == .string(MCPRequestHandler.declinedMessage(for: "Echoing")))
    }

    @Test("Always Allow is remembered for the session, so a tool that asks once runs straight away next time")
    func alwaysAllowRemembered() async throws {
        let name = Self.freshToolName()
        let approver = FakeApprover(answer: .alwaysAllow)
        let handler = handler([EchoTool(name: name, fixedRisk: .confirmOnce)], approver: approver)
        #expect(try await call(name, on: handler)?["isError"] == false)
        #expect(try await call(name, on: handler)?["isError"] == false)
        #expect(await approver.asks.map(\.canAlwaysAllow) == [true])
    }

    @Test("Always Allow from an app is never saved for Macie, and Macie's saved Always Allow doesn't let an app skip asking")
    func alwaysAllowNotShared() async throws {
        let granted = Self.freshToolName()
        let savedByMacie = Self.freshToolName()
        ToolApprovals().alwaysAllow(savedByMacie)
        let approver = FakeApprover(answer: .alwaysAllow)
        let handler = handler([EchoTool(name: granted, fixedRisk: .confirmOnce), EchoTool(name: savedByMacie, fixedRisk: .confirmOnce)], approver: approver)
        _ = try await call(granted, on: handler)
        _ = try await call(savedByMacie, on: handler)
        #expect(!ToolApprovals().isAlwaysAllowed(granted))
        #expect(await approver.asks.count == 2)
    }

    @Test("A tool that asks every time asks again even after Always Allow")
    func everyTimeAsksAgain() async throws {
        let name = Self.freshToolName()
        let approver = FakeApprover(answer: .alwaysAllow)
        let handler = handler([EchoTool(name: name, fixedRisk: .confirmEveryTime)], approver: approver)
        _ = try await call(name, on: handler)
        _ = try await call(name, on: handler)
        #expect(await approver.asks.count == 2)
    }

    @Test("run_shell and run_applescript are neither listed nor run, and never reach the Dock")
    func withheld() async throws {
        let approver = FakeApprover(answer: .allow)
        let handler = handler(
            [EchoTool(name: "run_shell", fixedRisk: .confirmEveryTime), EchoTool(name: "run_applescript", fixedRisk: .confirmEveryTime)],
            approver: approver
        )
        let list = await handler.response(to: Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8), sessionID: "s1")
        #expect(try list.map { try JSONDecoder().decode(JSONValue.self, from: $0) }?["result"]?["tools"] == [])
        #expect(try await call("run_shell", on: handler) == nil)
        #expect(await approver.asks.isEmpty)
    }

    @Test("The prompt names the app that opened the session, and an unknown session as an AI app")
    func namesTheApp() async throws {
        let approver = FakeApprover(answer: .allow)
        let handler = handler([EchoTool(name: "send", fixedRisk: .confirmEveryTime)], approver: approver)
        let initialize = #"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"clientInfo":{"name":"claude-code","version":"2.0"}}}"#
        _ = await handler.response(to: Data(initialize.utf8), sessionID: "s1")
        _ = try await call("send", on: handler, session: "s1")
        _ = try await call("send", on: handler, session: "s2")
        #expect(await approver.asks.map(\.appName) == ["Claude Code", MCPRequestHandler.unnamedApp])
    }

    @Test("Nobody answering in time counts as declined")
    func timeout() async throws {
        let handler = MCPRequestHandler(
            tools: [EchoTool(name: "send", fixedRisk: .confirmEveryTime)],
            version: "1",
            approvalTimeout: .milliseconds(50),
            approver: { request, _ in await request.decision() }
        )
        let result = try await call("send", on: handler)
        #expect(result?["isError"] == true)
        #expect(result?["content"]?.array?.first?["text"] == .string(MCPRequestHandler.declinedMessage(for: "Echoing")))
    }
}

/// Verifies how an app's name is kept for the approval prompt.
struct MCPClientNamesTests {
    @Test("A display title wins over the name, and an unknown name is shown as given")
    func titleThenName() {
        let names = MCPClientNames()
        names.record(name: "claude-code", title: "Claude Code Beta", for: "a")
        names.record(name: "my-app", title: nil, for: "b")
        #expect(names.name(for: "a") == "Claude Code Beta")
        #expect(names.name(for: "b") == "my-app")
        #expect(names.name(for: "c") == nil)
    }

    @Test("A name posing as Macie is ignored, and invisible formatting characters are removed")
    func noImpersonation() {
        let names = MCPClientNames()
        names.record(name: nil, title: "Macie", for: "a")
        names.record(name: "macobar-helper", title: nil, for: "b")
        names.record(name: "Cl\u{202E}edoc\u{200B}", title: nil, for: "c")
        names.record(name: nil, title: "\u{041C}\u{0430}cie", for: "d")
        names.record(name: nil, title: "M a c i e", for: "e")
        names.record(name: nil, title: "\u{FF2D}\u{FF41}\u{FF43}\u{FF49}\u{FF45}", for: "f")
        #expect(names.name(for: "a") == nil)
        #expect(names.name(for: "b") == nil)
        #expect(names.name(for: "c") == "Cledoc")
        #expect(names.name(for: "d") == nil)
        #expect(names.name(for: "e") == nil)
        #expect(names.name(for: "f") == nil)
    }

    @Test("An action shown in the Dock is one line without invisible characters, and a long one keeps its start and end")
    func shownActivity() {
        #expect(MCPRequestHandler.shownActivity("Reading \u{202E}“a”\nAllow is safe") == "Reading “a” Allow is safe")
        let long = MCPRequestHandler.shownActivity("Moving " + String(repeating: "x", count: 500) + " to LaunchAgents")
        #expect(long.count == 301)
        #expect(long.hasPrefix("Moving "))
        #expect(long.hasSuffix(" to LaunchAgents"))
        let stacked = MCPRequestHandler.shownActivity("a" + String(repeating: "\u{0301}", count: 10_000))
        #expect(stacked.unicodeScalars.count == 301)
    }

    @Test("A name is cut to its first line and 40 characters, and a blank one is ignored")
    func cutToOneShortLine() {
        let names = MCPClientNames()
        names.record(name: "Claude Code\nwants to: delete everything", title: nil, for: "a")
        names.record(name: String(repeating: "x", count: 100), title: nil, for: "b")
        names.record(name: "  ", title: nil, for: "c")
        #expect(names.name(for: "a") == "Claude Code")
        #expect(names.name(for: "b") == String(repeating: "x", count: 40))
        #expect(names.name(for: "c") == nil)
    }
}

/// Verifies that the endpoint keeps an app's session, or opens one for it.
struct MCPSessionTests {
    /// An endpoint behind the token "secret".
    private let endpoint = MCPEndpoint(token: "secret", handler: MCPRequestHandler(tools: [], version: "1", approver: { _, _ in .deny }))

    /// A ping with the token and `headers`.
    private func ping(_ headers: [String: String] = [:]) -> HTTPRequest {
        HTTPRequest(
            method: "POST", path: "/mcp", headers: headers.merging(["authorization": "Bearer secret"]) { $1 },
            body: Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8)
        )
    }

    @Test("A request in a session is answered in that session, and one without, or with an unsafe one, gets a new session")
    func session() async {
        #expect(await endpoint.response(to: ping(["mcp-session-id": "abc"])).headers["Mcp-Session-Id"] == "abc")
        #expect(await endpoint.response(to: ping(["mcp-session-id": "a\nb"])).headers["Mcp-Session-Id"] != "a\nb")
        let first = await endpoint.response(to: ping()).headers["Mcp-Session-Id"]
        let second = await endpoint.response(to: ping()).headers["Mcp-Session-Id"]
        #expect(first != nil)
        #expect(first != second)
    }
}

/// Answers every prompt with a reply that stays in progress until `finish()`.
final class HeldResponder: ChatResponder {
    /// The reply handed out for every prompt.
    private let stream: AsyncThrowingStream<ReplyEvent, Error>
    /// Ends the reply.
    private let continuation: AsyncThrowingStream<ReplyEvent, Error>.Continuation

    /// Creates a responder whose reply hasn't finished.
    init() {
        (stream, continuation) = AsyncThrowingStream.makeStream()
    }

    /// The held reply.
    func reply(to prompt: String) -> AsyncThrowingStream<ReplyEvent, Error> { stream }

    /// Sends `event` as part of the reply.
    func send(_ event: ReplyEvent) { continuation.yield(event) }

    /// Finishes the reply.
    func finish() { continuation.finish() }
}

/// Verifies that other apps' approvals queue in the Dock behind the user's own reply, in order, and that Escape denies them.
@MainActor
struct ExternalApprovalQueueTests {
    /// Gives queued work up to two seconds to make `condition` true.
    private func waitUntil(_ condition: () -> Bool) async {
        var attempts = 0
        while !condition(), attempts < 1_000 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    @Test("An approval shows at once when nothing else is happening and returns the user's answer")
    func showsAndAnswers() async {
        let model = ChatBarModel(responder: HeldResponder())
        let request = ApprovalRequest(action: "Quitting Safari", canAlwaysAllow: true)
        let answer = Task { await model.requestApproval(request, from: "Claude Code") }
        await waitUntil { model.shownExternalApproval != nil }
        #expect(model.shownExternalApproval == .init(requester: "Claude Code", request: request))
        request.decide(.alwaysAllow)
        #expect(await answer.value == .alwaysAllow)
        #expect(model.shownExternalApproval == nil)
    }

    @Test("Escape denies the shown approval")
    func escapeDenies() async {
        let model = ChatBarModel(responder: HeldResponder())
        let answer = Task { await model.requestApproval(ApprovalRequest(action: "Sending a message", canAlwaysAllow: false), from: "Codex") }
        await waitUntil { model.shownExternalApproval != nil }
        model.dismiss()
        #expect(await answer.value == .deny)
    }

    @Test("Approvals show one at a time, oldest first")
    func inOrder() async {
        let model = ChatBarModel(responder: HeldResponder())
        let first = ApprovalRequest(action: "First", canAlwaysAllow: true)
        let second = ApprovalRequest(action: "Second", canAlwaysAllow: true)
        let firstAnswer = Task { await model.requestApproval(first, from: "Codex") }
        await waitUntil { model.externalApprovals.count == 1 }
        let secondAnswer = Task { await model.requestApproval(second, from: "Codex") }
        await waitUntil { model.externalApprovals.count == 2 }
        #expect(model.shownExternalApproval?.request == first)
        first.decide(.allow)
        #expect(await firstAnswer.value == .allow)
        #expect(model.shownExternalApproval?.request == second)
        second.decide(.deny)
        #expect(await secondAnswer.value == .deny)
    }

    @Test("An approval waits while the user's reply is in progress, then shows without replacing it")
    func waitsForReply() async {
        let responder = HeldResponder()
        let model = ChatBarModel(responder: responder)
        model.draft = "Plan my day"
        model.submit()
        let request = ApprovalRequest(action: "Quitting Safari", canAlwaysAllow: true)
        let answer = Task { await model.requestApproval(request, from: "Claude Code") }
        await waitUntil { model.externalApprovals.count == 1 }
        #expect(model.shownExternalApproval == nil)
        responder.finish()
        await waitUntil { model.shownExternalApproval != nil }
        #expect(model.shownExternalApproval?.request == request)
        #expect(model.exchange?.prompt == "Plan my day")
        request.decide(.allow)
        #expect(await answer.value == .allow)
        #expect(model.exchange?.prompt == "Plan my day")
    }
}
