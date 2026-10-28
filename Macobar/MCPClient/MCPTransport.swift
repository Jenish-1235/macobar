/// Carries JSON-RPC messages to one MCP server and brings its replies back.
protocol MCPTransport: AnyObject, Sendable {
    /// Whether the connection can still carry messages; false once the process died or the session ended.
    var isOpen: Bool { get }
    /// Sends the request `message` and returns the server's reply to `id`.
    func request(_ message: JSONValue, id: Int) async throws -> JSONValue
    /// Sends the notification `message`, which gets no reply.
    func notify(_ message: JSONValue) async throws
    /// Ends the connection, stopping the server's process if there is one.
    func close()
}
