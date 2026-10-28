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

/// Verifies MCP's JSON-RPC answers and the safety policy over shared tools.
struct MCPRequestHandlerTests {
    /// A handler sharing the echo tool, a risky tool and the two withheld script tools; the user allows everything.
    private let handler = MCPRequestHandler(
        tools: [EchoTool(), EchoTool(name: "send", fixedRisk: .confirmEveryTime), EchoTool(name: "run_shell"), EchoTool(name: "run_applescript")],
        version: "1.2.3",
        approver: { _, _ in .allow }
    )

    /// The decoded response to `json`, or nil when there is none.
    private func respond(to json: String) async throws -> JSONValue? {
        guard let data = await handler.response(to: Data(json.utf8), sessionID: "test") else { return nil }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    @Test("initialize reports the protocol version, the tools capability and macobar's name")
    func initialize() async throws {
        let response = try await respond(to: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#)
        #expect(response?["id"] == 1)
        #expect(response?["result"]?["protocolVersion"] == "2025-06-18")
        #expect(response?["result"]?["capabilities"]?["tools"] == [:])
        #expect(response?["result"]?["serverInfo"] == ["name": "macobar", "version": "1.2.3"])
    }

    @Test("Notifications get no response")
    func notification() async throws {
        #expect(try await respond(to: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    }

    @Test("tools/list hides run_shell and run_applescript and gives each tool's schema")
    func listTools() async throws {
        let response = try await respond(to: #"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#)
        let tools = response?["result"]?["tools"]?.array ?? []
        #expect(tools.compactMap { $0["name"]?.string } == ["echo", "send"])
        #expect(tools.first?["inputSchema"] == EchoTool().parameters)
    }

    @Test("tools/call runs the tool and returns its text")
    func callTool() async throws {
        let response = try await respond(to: #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"echo","arguments":{"text":"hi"}}}"#)
        #expect(response?["result"] == ["content": [["type": "text", "text": "hi"]], "isError": false])
    }

    @Test("A failing tool comes back as an error result")
    func failingTool() async throws {
        let response = try await respond(to: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{}}}"#)
        #expect(response?["result"]?["isError"] == true)
        #expect(response?["result"]?["content"]?.array?.first?["text"] == "Missing required argument \"text\".")
    }

    @Test("A withheld tool can't be called")
    func withheldTool() async throws {
        let response = try await respond(to: #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"run_shell","arguments":{"text":"ls"}}}"#)
        #expect(response?["error"]?["code"] == -32602)
    }

    @Test("An unknown method is -32601")
    func unknownMethod() async throws {
        let response = try await respond(to: #"{"jsonrpc":"2.0","id":6,"method":"resources/list"}"#)
        #expect(response?["error"]?["code"] == -32601)
        #expect(response?["id"] == 6)
    }

    @Test("Bad JSON is -32700 with a null id")
    func badJSON() async throws {
        let response = try await respond(to: "{not json")
        #expect(response?["error"]?["code"] == -32700)
        #expect(response?["id"] == .null)
    }

    @Test("A batch is rejected as an invalid request")
    func batch() async throws {
        let response = try await respond(to: #"[{"jsonrpc":"2.0","id":7,"method":"ping"}]"#)
        #expect(response?["error"]?["code"] == -32600)
    }
}

/// Verifies the HTTP rules in front of MCP: path, method, token and origin.
struct MCPEndpointTests {
    /// An endpoint sharing the echo tool behind the token "secret".
    private let endpoint = MCPEndpoint(token: "secret", handler: MCPRequestHandler(tools: [EchoTool()], version: "1", approver: { _, _ in .deny }))

    /// A request to `path` with `headers` and a ping body.
    private func request(_ method: String = "POST", path: String = "/mcp", headers: [String: String]) -> HTTPRequest {
        HTTPRequest(method: method, path: path, headers: headers, body: Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8))
    }

    @Test("A POST with the token gets a JSON answer")
    func authorized() async {
        let response = await endpoint.response(to: request(headers: ["authorization": "Bearer secret", "origin": "http://localhost:6274"]))
        #expect(response.status == 200)
        #expect(response.headers["Content-Type"] == "application/json")
    }

    @Test("A missing or wrong token is 401")
    func unauthorized() async {
        #expect(await endpoint.response(to: request(headers: [:])).status == 401)
        #expect(await endpoint.response(to: request(headers: ["authorization": "Bearer secreT"])).status == 401)
    }

    @Test("A website origin is 403, even with the token")
    func foreignOrigin() async {
        let response = await endpoint.response(to: request(headers: ["authorization": "Bearer secret", "origin": "https://evil.example"]))
        #expect(response.status == 403)
    }

    @Test("A Host other than this Mac is 403, even with the token, and a local one is served")
    func foreignHost() async {
        #expect(await endpoint.response(to: request(headers: ["authorization": "Bearer secret", "host": "evil.example:7766"])).status == 403)
        #expect(await endpoint.response(to: request(headers: ["authorization": "Bearer secret", "host": "127.0.0.1.evil.example"])).status == 403)
        #expect(await endpoint.response(to: request(headers: ["authorization": "Bearer secret", "host": "127.0.0.1:7766"])).status == 200)
        #expect(await endpoint.response(to: request(headers: ["authorization": "Bearer secret", "host": "localhost:7766"])).status == 200)
        #expect(await endpoint.response(to: request(headers: ["authorization": "Bearer secret", "host": "[::1]:7766"])).status == 200)
    }

    @Test("GET is 405 and other paths are 404")
    func methodAndPath() async {
        #expect(await endpoint.response(to: request("GET", headers: ["authorization": "Bearer secret"])).status == 405)
        #expect(await endpoint.response(to: request(path: "/", headers: ["authorization": "Bearer secret"])).status == 404)
    }

    @Test("A notification is accepted with 202 and no body")
    func notification() async {
        let notification = HTTPRequest(
            method: "POST", path: "/mcp", headers: ["authorization": "Bearer secret"],
            body: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
        )
        let response = await endpoint.response(to: notification)
        #expect(response.status == 202)
        #expect(response.body.isEmpty)
    }
}

/// Verifies reading HTTP/1.1 requests off the socket.
struct HTTPRequestTests {
    @Test("A complete request is parsed with lowercased headers, the path without its query, and the body")
    func complete() throws {
        let raw = "POST /mcp?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 2\r\nAuthorization: Bearer t\r\n\r\n{}"
        let request = try HTTPRequest.parse(Data(raw.utf8))
        #expect(request == HTTPRequest(
            method: "POST", path: "/mcp",
            headers: ["host": "127.0.0.1", "content-length": "2", "authorization": "Bearer t"],
            body: Data("{}".utf8)
        ))
    }

    @Test("A request still arriving gives nil")
    func incomplete() throws {
        #expect(try HTTPRequest.parse(Data("POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\n{}".utf8)) == nil)
        #expect(try HTTPRequest.parse(Data("POST /mcp HTTP/1.1\r\nHost:".utf8)) == nil)
    }

    @Test("A body over 1 MB is too large")
    func tooLarge() {
        #expect(throws: HTTPRequestError.tooLarge) {
            try HTTPRequest.parse(Data("POST /mcp HTTP/1.1\r\nContent-Length: 1048577\r\n\r\n".utf8))
        }
    }

    @Test("A chunked body and a broken request line are refused")
    func refused() {
        #expect(throws: HTTPRequestError.lengthRequired) {
            try HTTPRequest.parse(Data("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8))
        }
        #expect(throws: HTTPRequestError.malformed) {
            try HTTPRequest.parse(Data("hello\r\n\r\n".utf8))
        }
    }

    @Test("A response is written with its length and closes the connection")
    func serializedResponse() {
        let response = HTTPResponse(status: 202)
        #expect(String(decoding: response.serialized, as: UTF8.self) == "HTTP/1.1 202 Accepted\r\nConnection: close\r\nContent-Length: 0\r\n\r\n")
    }
}

/// Verifies that the server turns connections away once its limit is reached.
struct MCPConnectionLimitTests {
    @Test("Connections are admitted up to the limit, and a closed one frees its place")
    func limit() {
        let limit = MCPConnectionLimit(maximum: 2)
        #expect(limit.admit())
        #expect(limit.admit())
        #expect(!limit.admit())
        limit.release()
        #expect(limit.admit())
    }
}

/// Verifies the access token's shape.
struct MCPAccessTokenTests {
    @Test("A token is 64 lowercase hex characters and new each time")
    func generate() {
        let token = MCPAccessToken.generate()
        #expect(token.count == 64)
        #expect(token.allSatisfy { "0123456789abcdef".contains($0) })
        #expect(token != MCPAccessToken.generate())
    }
}
