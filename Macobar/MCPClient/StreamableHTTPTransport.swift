import Foundation
import Synchronization

/// Talks to an MCP server over Streamable HTTP: each message is a POST answered with JSON or an event stream.
final class StreamableHTTPTransport: MCPTransport {
    /// Longest wait between bytes of a reply, in seconds.
    private static let timeout = 30.0
    /// Longest a whole exchange may take, so a server trickling bytes or streaming forever can't hang a prompt or a scheduled task.
    private static let longestExchange = Duration.seconds(120)
    /// The MCP revision sent in every request's header.
    private static let protocolVersion = "2025-06-18"
    /// A session of its own: no cookies or cache shared with the rest of macobar, and redirects only within the server's origin.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: SameOriginRedirects(), delegateQueue: nil)
    }()

    /// The session the server gave, and whether it has ended.
    private struct State {
        /// The `Mcp-Session-Id` the server returned, sent back with every later request.
        var sessionID: String?
        /// False once the server forgot the session.
        var isOpen = true
    }

    /// The server's MCP endpoint.
    private let url: URL
    /// Extra headers, such as Authorization, from the server's secrets.
    private let headers: [String: String]
    /// The session ID and whether the session is still alive.
    private let state = Mutex(State())

    /// Creates a transport posting to `url` with `headers`.
    init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }

    /// Whether the server still knows this session.
    var isOpen: Bool {
        state.withLock(\.isOpen)
    }

    /// Posts `message` and reads the reply to `id` from the JSON body or the event stream, closing the stream once it's in.
    func request(_ message: JSONValue, id: Int) async throws -> JSONValue {
        let request = try urlRequest(for: message)
        return try await Self.withDeadline { [self] in
            let (bytes, response) = try await Self.session.bytes(for: request)
            defer { bytes.task.cancel() }
            try check(response)
            if response.mimeType == "text/event-stream" {
                var reader = ServerSentEventReader()
                for try await line in NewlineSeparatedLines(bytes: bytes) {
                    guard let event = try reader.read(line: line) else { continue }
                    if let reply = (event.array ?? [event]).first(where: { JSONRPC.isReply($0, to: id) }) { return reply }
                }
                throw MCPClientError.closed
            }
            guard response.expectedContentLength <= JSONRPC.maximumMessageBytes else { throw MCPClientError.tooLarge }
            var body = Data()
            for try await byte in bytes {
                guard body.count < JSONRPC.maximumMessageBytes else { throw MCPClientError.tooLarge }
                body.append(byte)
            }
            guard let reply = try JSONRPC.messages(inJSON: body).first(where: { JSONRPC.isReply($0, to: id) }) else {
                throw MCPClientError.malformed
            }
            return reply
        }
    }

    /// Posts `message`; the server acknowledges without a reply, so any body is left unread.
    func notify(_ message: JSONValue) async throws {
        let request = try urlRequest(for: message)
        try await Self.withDeadline { [self] in
            let (bytes, response) = try await Self.session.bytes(for: request)
            bytes.task.cancel()
            try check(response)
        }
    }

    /// Nothing to release: each request is its own connection.
    func close() {}

    /// A POST of `message` with the MCP headers, the session ID once there is one, and the server's own headers; refuses plain http to another computer.
    private func urlRequest(for message: JSONValue) throws -> URLRequest {
        guard MCPServerConfig.isAllowedAddress(url) else { throw MCPClientError.insecureAddress }
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.httpBody = try message.encoded()
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(Self.protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID = state.withLock(\.sessionID) { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        return request
    }

    /// Keeps a returned session ID; throws on a non-success status, ending the session when the server forgot it.
    private func check(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw MCPClientError.malformed }
        let returnedSessionID = response.value(forHTTPHeaderField: "Mcp-Session-Id")
        let sessionEnded = state.withLock { state in
            state.sessionID = returnedSessionID ?? state.sessionID
            guard response.statusCode == 404, state.sessionID != nil else { return false }
            state.isOpen = false
            return true
        }
        if sessionEnded { throw MCPClientError.closed }
        guard (200..<300).contains(response.statusCode) else { throw MCPClientError.httpStatus(response.statusCode) }
    }

    /// Runs `exchange`, failing with `timedOut` (and cancelling it) once it takes longer than `longestExchange`.
    private static func withDeadline<Result: Sendable>(_ exchange: @escaping @Sendable () async throws -> Result) async throws -> Result {
        try await withThrowingTaskGroup(of: Result.self) { group in
            group.addTask { try await exchange() }
            group.addTask {
                try await Task.sleep(for: longestExchange)
                throw MCPClientError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw MCPClientError.closed }
            return result
        }
    }
}

/// Follows a redirect only to the same scheme, host and port, so a server's headers (its secrets) and messages never reach another host.
final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    /// Allows the redirect to `request` only when it stays at the origin the task was first sent to; otherwise the redirect response is returned as is.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        guard let original = task.originalRequest?.url, let target = request.url, Self.isSameOrigin(original, target) else { return nil }
        return request
    }

    /// Whether `first` and `second` share scheme, host and port (with the scheme's default port filled in).
    static func isSameOrigin(_ first: URL, _ second: URL) -> Bool {
        first.scheme?.lowercased() == second.scheme?.lowercased()
            && first.host()?.lowercased() == second.host()?.lowercased()
            && port(of: first) == port(of: second)
    }

    /// `url`'s port, or its scheme's default.
    private static func port(of url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : url.scheme?.lowercased() == "http" ? 80 : nil)
    }
}
