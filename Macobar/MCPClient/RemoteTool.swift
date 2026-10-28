/// A tool from a connected MCP server, offered to Macie like her own and run through the hub.
struct RemoteTool: VisualTool {
    /// Name the model calls it by: "<server>__<tool>", made safe for every provider.
    let name: String
    /// What the server says it does, prefixed with the server's name.
    let description: String
    /// The server's schema for its arguments.
    let parameters: JSONValue
    /// The connected server's name.
    private let serverName: String
    /// The server's own name for the tool.
    private let toolName: String
    /// Whether the user trusts the server to run tools without asking.
    private let isTrusted: Bool
    /// Runs the call, reconnecting to the server if needed.
    private let hub: MCPClientHub

    /// Wraps `info` from the server called `serverName`, run through `hub`.
    init(info: MCPToolInfo, serverName: String, isTrusted: Bool, hub: MCPClientHub) {
        name = RemoteToolName.make(server: serverName, tool: info.name)
        description = "From \(serverName): \(info.description)"
        parameters = info.inputSchema
        self.serverName = serverName
        toolName = info.name
        self.isTrusted = isTrusted
        self.hub = hub
    }

    /// Another program's tool may change anything, so it asks first unless the user trusts its server.
    func risk(for input: ToolInput) -> ToolRisk {
        isTrusted ? .none : .confirmOnce
    }

    /// Its result carries outside text the model will read, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Names the tool and its server; the server picks the tool's name, so it's shown made safe, and can't pose as another server or action in the approval prompt.
    func activity(for input: ToolInput) -> String {
        "Using \(RemoteToolName.shown(toolName)) from \(serverName)"
    }

    /// Asks the server to run the tool and returns its text and any images.
    func look(_ input: ToolInput) async throws -> (text: String, images: [ToolImage]) {
        try await hub.callTool(named: toolName, onServerNamed: serverName, arguments: input.arguments)
    }
}
