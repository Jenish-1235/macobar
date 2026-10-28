import Foundation

/// Builds the JSON-RPC 2.0 messages macobar sends to MCP servers and reads their replies.
enum JSONRPC {
    /// Largest message read from a server, in bytes; enough for a few screenshots, small enough that a hostile server can't exhaust memory.
    static let maximumMessageBytes = 32 << 20
    /// Deepest nesting of arrays and objects read from a server; decoding much deeper JSON overflows the stack and crashes macobar.
    static let maximumNesting = 64

    /// A request for `method` that expects a reply carrying `id`.
    static func request(id: Int, method: String, params: JSONValue? = nil) -> JSONValue {
        var message: [String: JSONValue] = ["jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method)]
        message["params"] = params
        return .object(message)
    }

    /// A notification for `method`, which gets no reply.
    static func notification(method: String) -> JSONValue {
        ["jsonrpc": "2.0", "method": .string(method)]
    }

    /// Whether `message` is the reply to the request carrying `id`.
    static func isReply(_ message: JSONValue, to id: Int) -> Bool {
        message["id"]?.number == Double(id) && (message["result"] != nil || message["error"] != nil)
    }

    /// The JSON value in `data`, refusing a body that's too large or nested too deeply to decode safely.
    static func value(fromJSON data: Data) throws -> JSONValue {
        guard data.count <= maximumMessageBytes else { throw MCPClientError.tooLarge }
        guard !isNestedTooDeeply(data), !isWideEncoding(data) else { throw MCPClientError.malformed }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw MCPClientError.malformed }
        return value
    }

    /// The messages in a JSON body: one object, or a batch of them.
    static func messages(inJSON body: Data) throws -> [JSONValue] {
        let value = try value(fromJSON: body)
        if let batch = value.array { return batch }
        guard value.object != nil else { throw MCPClientError.malformed }
        return [value]
    }

    /// The result `reply` carries, or the server's error.
    static func result(of reply: JSONValue) throws -> JSONValue {
        if let error = reply["error"] {
            throw MCPClientError.server(error["message"]?.string ?? error.jsonString)
        }
        guard let result = reply["result"] else { throw MCPClientError.malformed }
        return result
    }

    /// Whether `data` holds a zero byte, as UTF-16 or UTF-32 JSON always does and UTF-8 JSON never does; JSONDecoder reads those wider encodings, whose bytes can hide quotes and brackets from `isNestedTooDeeply`.
    static func isWideEncoding(_ data: Data) -> Bool {
        data.contains(0)
    }

    /// Whether `data` opens more than `maximumNesting` arrays and objects at once, counting brackets outside strings.
    static func isNestedTooDeeply(_ data: Data) -> Bool {
        var depth = 0
        var isInString = false
        var isEscaped = false
        for byte in data {
            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if byte == UInt8(ascii: "\\") {
                    isEscaped = true
                } else if byte == UInt8(ascii: "\"") {
                    isInString = false
                }
            } else if byte == UInt8(ascii: "\"") {
                isInString = true
            } else if byte == UInt8(ascii: "[") || byte == UInt8(ascii: "{") {
                depth += 1
                if depth > maximumNesting { return true }
            } else if byte == UInt8(ascii: "]") || byte == UInt8(ascii: "}") {
                depth -= 1
            }
        }
        return false
    }
}
