import Foundation

/// Why talking to an MCP server failed, in words the user (or the model) can act on.
enum MCPClientError: LocalizedError, Equatable {
    /// No reply within the request timeout.
    case timedOut
    /// The server answered with something that isn't MCP.
    case malformed
    /// The server returned a JSON-RPC error with this message.
    case server(String)
    /// The server answered with this non-success HTTP status.
    case httpStatus(Int)
    /// The command exited with this status before answering.
    case exited(command: String, status: Int32)
    /// The connection was closed or the session ended.
    case closed
    /// The server sent a message larger than macobar reads.
    case tooLarge
    /// The address is plain http to another computer, which would send its headers unencrypted.
    case insecureAddress

    /// The message, for `localizedDescription`.
    var errorDescription: String? {
        switch self {
        case .timedOut:
            "The server didn't answer in time. Check that it works, then press Test in Connections."
        case .malformed:
            "The server's answer isn't MCP. Check the command or address in Connections."
        case .server(let message):
            "The server said: \(message)"
        case .httpStatus(let status) where status == 401 || status == 403:
            "The server refused access (HTTP \(status)). Check the Authorization header in Connections."
        case .httpStatus(let status):
            "The server answered with HTTP \(status). Check the address in Connections."
        case .exited(let command, 127):
            "Couldn't find \(command). Install it, or enter its full path in Connections."
        case .exited(let command, let status):
            "\(command) stopped with status \(status). Check that the command works in Terminal."
        case .closed:
            "The connection to the server closed. Try again."
        case .tooLarge:
            "The server sent a reply too large to read. Check the server, then press Test in Connections."
        case .insecureAddress:
            "Use an https:// address; plain http:// is only for a server on this Mac. Fix it in Connections."
        }
    }
}
