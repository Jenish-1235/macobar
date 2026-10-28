import Foundation

/// Shows the user an action the named AI app wants to run and returns their answer.
typealias MCPApprover = @Sendable (_ request: ApprovalRequest, _ appName: String) async -> ApprovalDecision

/// Answers MCP's JSON-RPC messages: introduces macobar, lists the shared tools and runs them for an AI app.
struct MCPRequestHandler: Sendable {
    /// The MCP revision this server speaks.
    private static let protocolVersion = "2025-06-18"
    /// Tools never shared, since AI apps have shells of their own.
    private static let withheldToolNames: Set<String> = ["run_shell", "run_applescript"]
    /// Risk-free tools an app may run without asking: they neither read the user's data nor act for them in a way that matters, nor show text of the app's choosing as Macie's (as set_timer's notification does); every other tool asks in the Dock.
    private static let silentToolNames: Set<String> = [
        "system_status", "list_running_apps", "list_shortcuts", "music", "control_app", "arrange_window",
    ]
    /// Longest action line shown in the Dock, in Unicode scalars so stacked combining marks can't make one character huge; a longer one keeps its start and end.
    private static let maxActivityLength = 300
    /// What the Dock calls an app that didn't give its name.
    static let unnamedApp = "An AI app"
    /// What an approval that offers Always Allow says, since over MCP it lasts only for the app's session.
    static let sessionGrantReason = "Always Allow lasts until this app reconnects."

    /// Shared tools, by name.
    private let tools: [String: any Tool]
    /// macobar's version, reported to apps when they connect.
    private let version: String
    /// The tools the user always allows, per app session; Macie's own saved Always Allow never applies here, since an app's model may be steered by anything it read.
    private let sessionGrants = MCPSessionGrants()
    /// How long an approval waits for the user before it counts as declined.
    private let approvalTimeout: Duration
    /// Asks the user in the Dock.
    private let approver: MCPApprover
    /// Which app opened each session, for the approval prompt.
    private let clientNames = MCPClientNames()

    /// Shares `tools`, minus the withheld ones, reporting `version` as macobar's and asking `approver` before anything that reads the user's data or acts.
    init(
        tools: [any Tool],
        version: String,
        approvalTimeout: Duration = .seconds(120),
        approver: @escaping MCPApprover
    ) {
        let shared = tools.filter { !Self.withheldToolNames.contains($0.name) }
        self.tools = Dictionary(shared.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        self.version = version
        self.approvalTimeout = approvalTimeout
        self.approver = approver
    }

    /// The JSON-RPC response to `body` sent in `sessionID`, or nil for a notification, which gets none.
    func response(to body: Data, sessionID: String) async -> Data? {
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: body) else {
            return Self.reply(id: .null, error: .parseError)
        }
        guard message.array == nil else { return Self.reply(id: .null, error: .batchUnsupported) }
        guard message["jsonrpc"]?.string == "2.0", let method = message["method"]?.string else {
            return Self.reply(id: message["id"] ?? .null, error: .invalidRequest)
        }
        guard let id = message["id"] else { return nil }
        do throws(RPCError) {
            return Self.reply(id: id, result: try await result(of: method, params: message["params"], sessionID: sessionID))
        } catch {
            return Self.reply(id: id, error: error)
        }
    }

    /// What an AI app hears when the user didn't allow `activity`.
    static func declinedMessage(for activity: String) -> String {
        "The user didn't allow this in macobar: \(activity). Don't retry it; ask them what they'd like instead."
    }

    /// The result of calling `method` with `params` in `sessionID`.
    private func result(of method: String, params: JSONValue?, sessionID: String) async throws(RPCError) -> JSONValue {
        switch method {
        case "initialize":
            let client = params?["clientInfo"]
            clientNames.record(name: client?["name"]?.string, title: client?["title"]?.string, for: sessionID)
            return [
                "protocolVersion": .string(Self.protocolVersion),
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "macobar", "version": .string(version)],
            ]
        case "ping":
            return [:]
        case "tools/list":
            let listed = tools.values.sorted { $0.name < $1.name }.map { tool -> JSONValue in
                ["name": .string(tool.name), "description": .string(tool.description), "inputSchema": tool.parameters]
            }
            return ["tools": .array(listed)]
        case "tools/call":
            return try await callTool(params, sessionID: sessionID)
        default:
            throw .methodNotFound(method)
        }
    }

    /// Runs the tool `params` names once the user allows it; a refusal or failure comes back as an error result.
    private func callTool(_ params: JSONValue?, sessionID: String) async throws(RPCError) -> JSONValue {
        guard let name = params?["name"]?.string else { throw .invalidParams("tools/call needs the tool's name.") }
        guard let tool = tools[name] else { throw .invalidParams("Unknown tool: \(name).") }
        guard let arguments = (params?["arguments"] ?? [:]).object else { throw .invalidParams("The arguments must be an object.") }
        let input = ToolInput(arguments)
        let activity = tool.activity(for: input)
        guard await isAllowed(tool, input: input, activity: activity, sessionID: sessionID) else {
            return Self.toolResult(Self.declinedMessage(for: activity), isError: true)
        }
        do {
            if let visualTool = tool as? any VisualTool {
                let (text, images) = try await visualTool.look(input)
                return Self.toolResult(text, images: images, isError: false)
            }
            return Self.toolResult(try await tool.run(input), isError: false)
        } catch {
            return Self.toolResult(error.localizedDescription, isError: true)
        }
    }

    /// Whether the user lets `tool` run with `input`, asking in the Dock unless it's a silent risk-free tool or always allowed in this session; no answer in time is a no.
    private func isAllowed(_ tool: any Tool, input: ToolInput, activity: String, sessionID: String) async -> Bool {
        let risk = tool.risk(for: input)
        if risk == .none && Self.silentToolNames.contains(tool.name) { return true }
        let canAlwaysAllow = risk != .confirmEveryTime
        if canAlwaysAllow && sessionGrants.isGranted(tool.name, at: risk, in: sessionID) { return true }
        let request = ApprovalRequest(
            action: Self.shownActivity(activity),
            canAlwaysAllow: canAlwaysAllow,
            reason: canAlwaysAllow ? Self.sessionGrantReason : nil
        )
        let timeout = Task { [approvalTimeout] in
            try await Task.sleep(for: approvalTimeout)
            request.decide(.deny)
        }
        defer { timeout.cancel() }
        let decision = await approver(request, clientNames.name(for: sessionID) ?? Self.unnamedApp)
        if decision == .alwaysAllow && canAlwaysAllow { sessionGrants.grant(tool.name, at: risk, in: sessionID) }
        return decision != .deny
    }

    /// `activity` as one line for the Dock: no line breaks or invisible characters an app could use to dress up its request, and a long one keeps its start and end.
    static func shownActivity(_ activity: String) -> String {
        let line = MCPClientNames.visible(activity).unicodeScalars
        guard line.count > maxActivityLength else { return String(line) }
        let half = maxActivityLength / 2
        return String(String.UnicodeScalarView(line.prefix(half))) + "…" + String(String.UnicodeScalarView(line.suffix(half)))
    }

    /// A tools/call result: the text (or "Done."), then any images.
    private static func toolResult(_ text: String, images: [ToolImage] = [], isError: Bool) -> JSONValue {
        let textContent: JSONValue = ["type": "text", "text": .string(text.isEmpty ? "Done." : text)]
        let imageContent = images.map { image -> JSONValue in
            ["type": "image", "data": .string(image.data.base64EncodedString()), "mimeType": .string(image.mediaType)]
        }
        return ["content": .array([textContent] + imageContent), "isError": .bool(isError)]
    }

    /// A success response carrying `result`.
    private static func reply(id: JSONValue, result: JSONValue) -> Data {
        Data(JSONValue.object(["jsonrpc": "2.0", "id": id, "result": result]).jsonString.utf8)
    }

    /// An error response carrying `error`.
    private static func reply(id: JSONValue, error: RPCError) -> Data {
        let body: JSONValue = ["code": .number(Double(error.code)), "message": .string(error.message)]
        return Data(JSONValue.object(["jsonrpc": "2.0", "id": id, "error": body]).jsonString.utf8)
    }
}

/// A JSON-RPC error: its standard code and a message for the app.
private struct RPCError: Error {
    /// The JSON-RPC error code.
    let code: Int
    /// What went wrong.
    let message: String

    /// The body isn't JSON.
    static let parseError = RPCError(code: -32700, message: "Parse error: the body isn't valid JSON.")
    /// The JSON isn't a JSON-RPC 2.0 request.
    static let invalidRequest = RPCError(code: -32600, message: "Invalid request: expected a JSON-RPC 2.0 object with a method.")
    /// A batch (array) of messages, which MCP no longer uses.
    static let batchUnsupported = RPCError(code: -32600, message: "Batches aren't supported; send one JSON-RPC message per request.")

    /// No method called `method`.
    static func methodNotFound(_ method: String) -> RPCError {
        RPCError(code: -32601, message: "Method not found: \(method).")
    }

    /// The params are missing something or name something unknown.
    static func invalidParams(_ message: String) -> RPCError {
        RPCError(code: -32602, message: message)
    }
}
