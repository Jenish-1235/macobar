import Foundation

/// Reads JSON-RPC messages from a `text/event-stream` body, one line at a time.
struct ServerSentEventReader {
    /// `data:` payloads of the event being read, joined when the event ends.
    private var pendingData: [String] = []
    /// Bytes in `pendingData`, so an event that never ends can't grow without limit.
    private var pendingBytes = 0

    /// Takes the next line and returns a message once one is whole: a single `data:` line at once, several when their event ends; throws when an event grows too large.
    mutating func read(line: String) throws -> JSONValue? {
        if line.isEmpty {
            defer { pendingData = []; pendingBytes = 0 }
            return pendingData.count > 1 ? Self.message(in: pendingData.joined(separator: "\n")) : nil
        }
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5)
        let data = String(payload.first == " " ? payload.dropFirst() : payload)
        guard !pendingData.isEmpty || data.hasPrefix("{") || data.hasPrefix("[") else { return nil }
        pendingData.append(data)
        pendingBytes += data.utf8.count
        guard pendingBytes <= JSONRPC.maximumMessageBytes else { throw MCPClientError.tooLarge }
        guard pendingData.count == 1, let message = Self.message(in: data) else { return nil }
        pendingData = []
        pendingBytes = 0
        return message
    }

    /// The JSON-RPC message (an object or a batch) in `text`, or nil when it isn't one.
    private static func message(in text: String) -> JSONValue? {
        guard let message = try? JSONRPC.value(fromJSON: Data(text.utf8)), message.object != nil || message.array != nil else { return nil }
        return message
    }
}
