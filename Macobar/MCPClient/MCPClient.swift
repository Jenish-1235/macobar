import Foundation
import Synchronization

/// One live MCP session with a server: the handshake, listing its tools and calling them.
final class MCPClient: Sendable {
    /// The MCP revision macobar speaks.
    private static let protocolVersion = "2025-06-18"
    /// Most tools/list pages followed, so a server repeating its cursor can't loop forever.
    private static let maximumPages = 50
    /// Most tools kept from one server; every prompt sends them all, so a server can't flood the model's context.
    private static let maximumTools = 256

    /// Carries the messages.
    private let transport: any MCPTransport
    /// The last request id used; each request takes the next.
    private let lastID = Atomic(0)

    /// Wraps `transport`; call `connect(over:)` instead, which also does the handshake.
    private init(transport: any MCPTransport) {
        self.transport = transport
    }

    /// Opens a session over `transport`: initialize, then notifications/initialized.
    static func connect(over transport: any MCPTransport) async throws -> MCPClient {
        let client = MCPClient(transport: transport)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        _ = try await client.send("initialize", params: [
            "protocolVersion": .string(protocolVersion),
            "capabilities": [:],
            "clientInfo": ["name": "macobar", "version": .string(version)],
        ])
        try await transport.notify(JSONRPC.notification(method: "notifications/initialized"))
        return client
    }

    /// Every tool the server offers, following its pages, up to `maximumTools`.
    func listTools() async throws -> [MCPToolInfo] {
        var tools: [MCPToolInfo] = []
        var cursor: String?
        for _ in 0..<Self.maximumPages {
            let page = try MCPToolInfo.page(from: try await send("tools/list", params: cursor.map { ["cursor": .string($0)] }))
            tools += page.tools
            guard tools.count < Self.maximumTools, let next = page.nextCursor else { break }
            cursor = next
        }
        return Array(tools.prefix(Self.maximumTools))
    }

    /// Runs the server's tool `name` with `arguments` and returns its text and images.
    func callTool(named name: String, arguments: [String: JSONValue]) async throws -> (text: String, images: [ToolImage]) {
        try MCPToolOutput.parse(try await send("tools/call", params: ["name": .string(name), "arguments": .object(arguments)]))
    }

    /// Sends a `method` request with `params` and returns its result.
    private func send(_ method: String, params: JSONValue?) async throws -> JSONValue {
        let id = lastID.add(1, ordering: .relaxed).newValue
        return try JSONRPC.result(of: try await transport.request(JSONRPC.request(id: id, method: method, params: params), id: id))
    }
}
