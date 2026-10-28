import Foundation

/// Sends JSON-RPC messages to macobar's MCP endpoint and keeps the session macobar opens, so it knows which app is asking.
actor MacobarConnection {
    /// Longest wait for an answer; longer than macobar's two minutes for an approval, so macobar decides.
    private static let timeout: TimeInterval = 180

    /// A session that never goes through a proxy or caches anything, so the token only ever reaches 127.0.0.1.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }()

    /// macobar's MCP endpoint.
    private let endpoint: URL
    /// The token from macobar's Share Tools window.
    private let token: String
    /// The session macobar opened, sent with every later message.
    private var sessionID: String?

    /// Talks to `endpoint` with `token`.
    init(endpoint: URL, token: String) {
        self.endpoint = endpoint
        self.token = token
    }

    /// macobar's answer to `message`, an error answer when macobar can't be reached, or nil for a notification.
    func send(_ message: Data) async -> Data? {
        var request = URLRequest(url: endpoint, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.httpBody = message
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        do {
            let (body, response) = try await Self.session.data(for: request)
            guard let response = response as? HTTPURLResponse else { return Self.failure(answering: message, "macobar sent an answer that isn't HTTP.") }
            if let sessionID = response.value(forHTTPHeaderField: "Mcp-Session-Id") { self.sessionID = sessionID }
            switch response.statusCode {
            case 200: return body
            case 202: return nil
            case 401: return Self.failure(answering: message, "macobar refused the token. Copy the Claude Desktop config again from macobar's Share Tools window.")
            default: return Self.failure(answering: message, "macobar answered \(response.statusCode): \(String(decoding: body, as: UTF8.self))")
            }
        } catch {
            return Self.failure(answering: message, "Couldn't reach macobar: \(error.localizedDescription) Open macobar and turn on Share Tools with AI Apps.")
        }
    }

    /// A JSON-RPC error answering `message` with `text`, or nil when `message` is a notification and expects no answer.
    private static func failure(answering message: Data, _ text: String) -> Data? {
        guard let request = try? JSONSerialization.jsonObject(with: message) as? [String: Any], let id = request["id"] else { return nil }
        let answer: [String: Any] = ["jsonrpc": "2.0", "id": id, "error": ["code": -32000, "message": text]]
        return try? JSONSerialization.data(withJSONObject: answer)
    }
}

/// Writes whole lines to standard output, one at a time, so answers finishing together never interleave.
actor LineWriter {
    /// Writes `line` and a newline.
    func write(_ line: Data) {
        FileHandle.standardOutput.write(line + Data("\n".utf8))
    }
}

guard let token = ProcessInfo.processInfo.environment["MACOBAR_TOKEN"], !token.isEmpty else {
    FileHandle.standardError.write(Data("macobar-mcp: set MACOBAR_TOKEN to the token from macobar's Share Tools window.\n".utf8))
    exit(1)
}
guard let endpoint = URL(string: "http://127.0.0.1:7766/mcp") else { exit(1) }

/// macobar, reached over HTTP.
let connection = MacobarConnection(endpoint: endpoint, token: token)
/// Standard output, where answers go.
let output = LineWriter()
/// The message being read, up to its newline.
var message = Data()
// Split on "\n" alone: JSON may carry U+2028 or U+0085 unescaped, which `lines` would also split on.
for try await byte in FileHandle.standardInput.bytes {
    guard byte == UInt8(ascii: "\n") else {
        message.append(byte)
        continue
    }
    if !message.isEmpty {
        Task { [message] in
            if let answer = await connection.send(message) { await output.write(answer) }
        }
    }
    message = Data()
}
