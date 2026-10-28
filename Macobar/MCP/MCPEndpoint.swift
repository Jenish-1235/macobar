import Foundation

/// The HTTP rules in front of MCP: one path, POST only, the bearer token, and no requests from websites.
struct MCPEndpoint: Sendable {
    /// The only path served.
    static let path = "/mcp"
    /// The header carrying the MCP session, which tells apart the apps connected at once.
    private static let sessionHeader = "Mcp-Session-Id"
    /// Hosts a browser `Origin` or the `Host` header may name; anything else could be a website reaching in through DNS rebinding.
    private static let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    /// The secret every request must carry as `Authorization: Bearer <token>`.
    private let token: String
    /// Answers the JSON-RPC messages.
    private let handler: MCPRequestHandler

    /// Serves `handler` to requests that carry `token`.
    init(token: String, handler: MCPRequestHandler) {
        self.token = token
        self.handler = handler
    }

    /// The response to `request`: refusals first, then the JSON-RPC answer (202 with no body for a notification), in the request's session or a new one.
    func response(to request: HTTPRequest) async -> HTTPResponse {
        guard Self.isLocalOrigin(request.headers["origin"]), Self.isLocalHost(request.headers["host"]) else {
            return .text(403, "Requests from websites aren't allowed.")
        }
        guard request.path == Self.path else { return .text(404, "Not found. The MCP endpoint is \(Self.path).") }
        guard isAuthorized(request.headers["authorization"]) else {
            return .text(401, "Missing or wrong token. Copy it from macobar's Share Tools window.", headers: ["WWW-Authenticate": "Bearer"])
        }
        guard request.method == "POST" else { return .text(405, "Only POST is supported.", headers: ["Allow": "POST"]) }
        let sessionID = Self.sessionID(in: request.headers[Self.sessionHeader.lowercased()]) ?? UUID().uuidString
        guard let body = await handler.response(to: request.body, sessionID: sessionID) else {
            return HTTPResponse(status: 202, headers: [Self.sessionHeader: sessionID])
        }
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json", Self.sessionHeader: sessionID], body: body)
    }

    /// The response to a request that couldn't be read.
    static func response(to error: HTTPRequestError) -> HTTPResponse {
        switch error {
        case .malformed: .text(400, "That isn't a valid HTTP/1.1 request.")
        case .tooLarge: .text(413, "Requests are limited to \(HTTPRequest.maxBodyBytes) bytes.")
        case .lengthRequired: .text(411, "Send the body with Content-Length, not chunked.")
        }
    }

    /// The session `header` names, if it's visible ASCII as MCP requires, so it's safe to echo back as a header.
    private static func sessionID(in header: String?) -> String? {
        guard let header, !header.isEmpty, header.utf8.allSatisfy({ (0x21...0x7E).contains($0) }) else { return nil }
        return header
    }

    /// Whether `origin` is absent (not a browser) or names this Mac.
    private static func isLocalOrigin(_ origin: String?) -> Bool {
        guard let origin else { return true }
        guard let host = URL(string: origin)?.host()?.lowercased() else { return false }
        return localHosts.contains(host)
    }

    /// Whether the `Host` header is absent or names this Mac, so a website whose name was rebound to 127.0.0.1 is refused.
    private static func isLocalHost(_ host: String?) -> Bool {
        guard let host else { return true }
        let name = host.hasPrefix("[") ? host.dropFirst().prefix { $0 != "]" } : host.prefix { $0 != ":" }
        return localHosts.contains(name.lowercased())
    }

    /// Whether `authorization` is `Bearer <token>`, compared in constant time so the token can't be guessed byte by byte.
    private func isAuthorized(_ authorization: String?) -> Bool {
        let prefix = "Bearer "
        guard let authorization, authorization.hasPrefix(prefix) else { return false }
        let given = Array(authorization.utf8.dropFirst(prefix.utf8.count))
        let expected = Array(token.utf8)
        guard given.count == expected.count else { return false }
        return zip(given, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
