import Foundation
import Testing

/// Verifies the MCP client's pure parts: tool names, command lines, saved servers and secrets, and reading replies.
struct MCPClientTests {
    /// A store backed by a file of its own in the temporary folder.
    private let store = MCPServerStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "MCPClientTests-\(UUID().uuidString).json"))

    @Test("A tool name joins server and tool with two underscores")
    func plainToolName() {
        #expect(RemoteToolName.make(server: "github", tool: "create_issue") == "github__create_issue")
    }

    @Test("Hyphens, capitals and other characters become safe")
    func sanitizedToolName() {
        #expect(RemoteToolName.make(server: "my-server", tool: "Get Page!") == "my_server__get_page_")
    }

    @Test("A long tool name is cut to 64 characters, the same way every time")
    func longToolName() {
        let tool = String(repeating: "a", count: 80)
        let name = RemoteToolName.make(server: "notion", tool: tool)
        #expect(name.count == 64)
        #expect(name.hasPrefix("notion__aaaa"))
        #expect(name == RemoteToolName.make(server: "notion", tool: tool))
        #expect(name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") })
    }

    @Test("Long tool names that differ only at the end stay different")
    func longToolNamesStayUnique() {
        let prefix = String(repeating: "b", count: 70)
        #expect(RemoteToolName.make(server: "linear", tool: prefix + "1") != RemoteToolName.make(server: "linear", tool: prefix + "2"))
    }

    @Test("A command line splits on spaces and keeps quoted and escaped words whole")
    func commandLineWords() {
        let words = CommandLineWords.split(#"npx -y "@scope/pkg name"  'a "b"' c\ d """#)
        #expect(words == ["npx", "-y", "@scope/pkg name", #"a "b""#, "c d", ""])
    }

    @Test("A blank command line has no words")
    func blankCommandLine() {
        #expect(CommandLineWords.split("   ").isEmpty)
    }

    @Test("Saved servers read back the same, with trust changes kept")
    func storeRoundTrip() throws {
        let command = MCPServerConfig(name: "github", transport: .command(executable: "npx", arguments: ["-y", "@modelcontextprotocol/server-github"]))
        let address = MCPServerConfig(name: "linear-2", transport: .address(url: try #require(URL(string: "https://mcp.linear.app/mcp"))))
        try store.add(command)
        try store.add(address)
        try store.setTrusted(true, forServerNamed: "linear-2")
        var trusted = address
        trusted.isTrusted = true
        #expect(try store.servers() == [command, trusted])
        try store.remove(named: "github")
        #expect(try store.servers() == [trusted])
    }

    @Test("A taken or malformed name is refused")
    func storeRefusesBadNames() throws {
        let server = MCPServerConfig(name: "files", transport: .command(executable: "uvx", arguments: []))
        try store.add(server)
        #expect(throws: MCPServerStoreError.duplicateName("files")) { try store.add(server) }
        #expect(throws: MCPServerStoreError.invalidName) {
            try store.add(MCPServerConfig(name: "My Files", transport: .command(executable: "uvx", arguments: [])))
        }
    }

    @Test("Secret lines become values, skipping blanks and keeping = in values")
    func secretLines() throws {
        let values = try MCPServerSecrets.values(fromLines: "GITHUB_TOKEN=ghp_1\n\n  Authorization = Bearer a=b  \n")
        #expect(values == ["GITHUB_TOKEN": "ghp_1", "Authorization": "Bearer a=b"])
    }

    @Test("A secret line without = is refused")
    func badSecretLine() {
        #expect(throws: MCPSecretLineError()) { try MCPServerSecrets.values(fromLines: "TOKEN ghp_1") }
    }

    @Test("A request carries its id, method and params")
    func requestMessage() {
        #expect(JSONRPC.request(id: 3, method: "tools/list") == ["jsonrpc": "2.0", "id": 3, "method": "tools/list"])
        #expect(JSONRPC.request(id: 4, method: "tools/call", params: ["name": "x"])["params"] == ["name": "x"])
    }

    @Test("Only a message with the request's id and a result or error is its reply")
    func replyMatching() {
        #expect(JSONRPC.isReply(["jsonrpc": "2.0", "id": 2, "result": [:]], to: 2))
        #expect(!JSONRPC.isReply(["jsonrpc": "2.0", "id": 1, "result": [:]], to: 2))
        #expect(!JSONRPC.isReply(["jsonrpc": "2.0", "id": 2, "method": "ping"], to: 2))
    }

    @Test("A JSON body holds one message or a batch")
    func jsonBodies() throws {
        #expect(try JSONRPC.messages(inJSON: Data(#"{"id":1,"result":{}}"#.utf8)).count == 1)
        #expect(try JSONRPC.messages(inJSON: Data(#"[{"method":"a"},{"id":1,"result":{}}]"#.utf8)).count == 2)
        #expect(throws: MCPClientError.malformed) { try JSONRPC.messages(inJSON: Data("<html>".utf8)) }
    }

    @Test("A reply's result is returned and its error thrown with the server's message")
    func replyResult() throws {
        #expect(try JSONRPC.result(of: ["id": 1, "result": ["ok": true]]) == ["ok": true])
        #expect(throws: MCPClientError.server("Unknown tool")) {
            try JSONRPC.result(of: ["id": 1, "error": ["code": -32602, "message": "Unknown tool"]])
        }
    }

    @Test("An event stream yields each data payload as a message")
    func eventStream() throws {
        var reader = ServerSentEventReader()
        let lines = ["event: message", #"data: {"id":1,"#, #"data: "result":{}}"#, "", "data: ping", #"data:{"id":2,"result":{}}"#]
        let messages = try lines.compactMap { try reader.read(line: $0) }
        #expect(messages == [["id": 1, "result": [:]], ["id": 2, "result": [:]]])
    }

    @Test("JSON nested deeper than the limit is refused before decoding, so it can't overflow the stack")
    func deepNestingRefused() throws {
        let deep = String(repeating: "[", count: 10_000) + String(repeating: "]", count: 10_000)
        #expect(throws: MCPClientError.malformed) { try JSONRPC.messages(inJSON: Data(deep.utf8)) }
        let shallow = #"{"id":1,"result":{"text":"[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[\"[["}}"#
        #expect(try JSONRPC.messages(inJSON: Data(shallow.utf8)).count == 1)
    }

    @Test("Deep JSON in UTF-16, whose bytes hide brackets from the depth check, is refused")
    func wideEncodingRefused() throws {
        let deep = "[\"\u{2241}\"," + String(repeating: "[", count: 100) + String(repeating: "]", count: 100) + "]"
        let data = try #require(deep.data(using: .utf16LittleEndian))
        #expect(!JSONRPC.isNestedTooDeeply(data))
        #expect(throws: MCPClientError.malformed) { try JSONRPC.messages(inJSON: data) }
    }

    @Test("A line longer than the limit throws instead of growing without end")
    func oversizeLine() async {
        let bytes = AsyncStream<UInt8> { continuation in
            "short\nmuch too long".utf8.forEach { continuation.yield($0) }
            continuation.finish()
        }
        await #expect(throws: MCPClientError.tooLarge) {
            for try await _ in NewlineSeparatedLines(bytes: bytes, maximumLength: 8) {}
        }
    }

    @Test("A server name can't start or end with a hyphen or double one, so tool names never collide across servers")
    func serverNameHyphens() {
        #expect(MCPServerConfig.isValidName("linear-2"))
        #expect(!MCPServerConfig.isValidName("a-"))
        #expect(!MCPServerConfig.isValidName("-a"))
        #expect(!MCPServerConfig.isValidName("a--b"))
    }

    @Test("Addresses must be https, or http only to this Mac")
    func allowedAddresses() throws {
        #expect(MCPServerConfig.isAllowedAddress(try #require(URL(string: "https://mcp.linear.app/mcp"))))
        #expect(MCPServerConfig.isAllowedAddress(try #require(URL(string: "http://localhost:3000/mcp"))))
        #expect(MCPServerConfig.isAllowedAddress(try #require(URL(string: "http://127.0.0.1:3000/mcp"))))
        #expect(!MCPServerConfig.isAllowedAddress(try #require(URL(string: "http://example.com/mcp"))))
        #expect(!MCPServerConfig.isAllowedAddress(try #require(URL(string: "http://192.168.1.20/mcp"))))
        #expect(!MCPServerConfig.isAllowedAddress(try #require(URL(string: "ftp://example.com/mcp"))))
    }

    @Test("Redirects are followed only within the same scheme, host and port")
    func sameOriginRedirects() throws {
        let server = try #require(URL(string: "https://mcp.example.com/mcp"))
        #expect(SameOriginRedirects.isSameOrigin(server, try #require(URL(string: "https://MCP.example.com:443/mcp/"))))
        #expect(!SameOriginRedirects.isSameOrigin(server, try #require(URL(string: "https://evil.example.net/mcp"))))
        #expect(!SameOriginRedirects.isSameOrigin(server, try #require(URL(string: "http://mcp.example.com/mcp"))))
        #expect(!SameOriginRedirects.isSameOrigin(server, try #require(URL(string: "https://mcp.example.com:8443/mcp"))))
    }

    @Test("A server process gets only basic variables from macobar, plus the login PATH and its own secrets")
    func childEnvironment() {
        let inherited = ["HOME": "/Users/me", "OPENAI_API_KEY": "sk-1", "SSH_AUTH_SOCK": "/tmp/agent", "PATH": "/usr/bin"]
        let environment = StdioTransport.childEnvironment(inheriting: inherited, path: "/opt/homebrew/bin:/usr/bin", secrets: ["GITHUB_TOKEN": "ghp_1"])
        #expect(environment == ["HOME": "/Users/me", "PATH": "/opt/homebrew/bin:/usr/bin", "GITHUB_TOKEN": "ghp_1"])
    }

    @Test("A tool name shown in the approval prompt keeps only safe characters")
    func shownToolName() {
        #expect(RemoteToolName.shown("create_issue") == "create_issue")
        #expect(RemoteToolName.shown("read\nfrom github (safe)\u{202E}") == "read_from_github__safe__")
        #expect(RemoteToolName.shown(String(repeating: "x", count: 500)).count == RemoteToolName.maximumLength)
    }

    @Test("A tools/list page cuts long descriptions and leaves out tools with oversized names or schemas")
    func toolPageLimits() throws {
        let hugeSchema: JSONValue = ["type": "object", "description": .string(String(repeating: "x", count: MCPToolInfo.maximumSchemaBytes))]
        let result: JSONValue = [
            "tools": [
                ["name": "wordy", "description": .string(String(repeating: "d", count: 10_000))],
                ["name": "bloated", "inputSchema": hugeSchema],
                ["name": .string(String(repeating: "n", count: MCPToolInfo.maximumNameLength + 1))],
            ],
        ]
        let page = try MCPToolInfo.page(from: result)
        #expect(page.tools.map(\.name) == ["wordy"])
        #expect(page.tools.first?.description.count == MCPToolInfo.maximumDescriptionLength)
    }

    @Test("Lines split only at newlines, keeping blank lines and U+2028 inside a line")
    func newlineSeparatedLines() async throws {
        let bytes = AsyncStream<UInt8> { continuation in
            "{\"text\":\"a\u{2028}b\"}\r\n\ndata: x".utf8.forEach { continuation.yield($0) }
            continuation.finish()
        }
        var lines: [String] = []
        for try await line in NewlineSeparatedLines(bytes: bytes) { lines.append(line) }
        #expect(lines == ["{\"text\":\"a\u{2028}b\"}", "", "data: x"])
    }

    @Test("A tools/list page gives each tool, an empty schema when none is given, and the next cursor")
    func toolPage() throws {
        let result: JSONValue = [
            "tools": [
                ["name": "search", "description": "Searches.", "inputSchema": ["type": "object", "properties": ["q": ["type": "string"]]]],
                ["name": "ping"],
                ["description": "No name, so skipped."],
            ],
            "nextCursor": "page2",
        ]
        let page = try MCPToolInfo.page(from: result)
        #expect(page.tools.map(\.name) == ["search", "ping"])
        #expect(page.tools[1].inputSchema == Schema.object())
        #expect(page.tools[1].description.isEmpty)
        #expect(page.nextCursor == "page2")
    }

    @Test("A tool result joins its text and decodes its images, leaving out types models can't take")
    func toolOutput() throws {
        let image = Data([1, 2, 3])
        let result: JSONValue = [
            "content": [
                ["type": "text", "text": "First"],
                ["type": "image", "data": .string(image.base64EncodedString()), "mimeType": "image/png"],
                ["type": "image", "data": .string(image.base64EncodedString()), "mimeType": "image/svg+xml"],
                ["type": "text", "text": "Second"],
            ],
        ]
        let output = try MCPToolOutput.parse(result)
        #expect(output.text == "First\nSecond")
        #expect(output.images == [ToolImage(data: image, mediaType: "image/png")])
    }

    @Test("A tool result marked as an error throws its text")
    func toolOutputError() {
        let result: JSONValue = ["content": [["type": "text", "text": "Repository not found"]], "isError": true]
        #expect(throws: ToolError.self) { try MCPToolOutput.parse(result) }
    }
}
