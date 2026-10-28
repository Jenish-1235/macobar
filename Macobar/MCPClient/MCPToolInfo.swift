/// One tool as an MCP server lists it.
struct MCPToolInfo: Equatable, Sendable {
    /// Longest tool name kept, as the MCP spec allows; a longer one is left out.
    static let maximumNameLength = 128
    /// Longest description kept, in characters; every prompt sends it, so a server can't flood the model's context or the user's bill.
    static let maximumDescriptionLength = 2_048
    /// Largest input schema kept, in bytes of JSON; a tool with a larger one is left out for the same reason.
    static let maximumSchemaBytes = 65_536

    /// The server's own name for the tool.
    let name: String
    /// What the server says the tool does, cut to `maximumDescriptionLength`.
    let description: String
    /// JSON Schema of its arguments; an empty object schema when the server gave none.
    let inputSchema: JSONValue

    /// The tools on one page of a tools/list result, and the cursor of the next page if there is one; tools with an oversized name or schema are left out.
    static func page(from result: JSONValue) throws -> (tools: [MCPToolInfo], nextCursor: String?) {
        guard let listed = result["tools"]?.array else { throw MCPClientError.malformed }
        let tools = listed.compactMap { tool -> MCPToolInfo? in
            guard let name = tool["name"]?.string, !name.isEmpty, name.count <= maximumNameLength else { return nil }
            let schema = tool["inputSchema"].flatMap { $0.object == nil ? nil : $0 } ?? Schema.object()
            guard schema.jsonString.utf8.count <= maximumSchemaBytes else { return nil }
            let description = String((tool["description"]?.string ?? "").prefix(maximumDescriptionLength))
            return MCPToolInfo(name: name, description: description, inputSchema: schema)
        }
        return (tools, result["nextCursor"]?.string)
    }
}
