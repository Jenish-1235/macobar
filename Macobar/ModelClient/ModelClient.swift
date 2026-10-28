import Foundation

/// What a streamed reply produces: text as it arrives, then the complete turn.
enum ModelEvent: Sendable {
    /// More reply text.
    case text(String)
    /// The whole turn, including any tool calls.
    case finished(AssistantTurn)
}

/// Sends a conversation to the active provider and streams the reply back.
struct ModelClient: Sendable {
    /// Largest error body read when a request is refused.
    private static let errorBodyLimit = 64 * 1024

    /// Model requests use.
    private let model: String
    /// Where requests go and how they're authenticated.
    private let endpoint: ProviderEndpoint
    /// How requests and replies are shaped.
    private let format: any WireFormat
    /// The HTTP session; injectable for tests.
    private let session: URLSession

    /// Creates a client for `account`, authenticated with `credential`.
    init(account: ProviderAccount, credential: String, session: URLSession = .shared) throws {
        model = account.model
        endpoint = try ProviderEndpoint(account: account, credential: credential)
        format = account.wireFormat
        self.session = session
    }

    /// Streams the model's reply to `conversation` with `tools` available.
    func streamReply(instructions: String, conversation: [ConversationItem], tools: [ToolDefinition] = []) -> AsyncThrowingStream<ModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(instructions: instructions, conversation: conversation, tools: tools)
                    // Redirects aren't followed, so the credential in the headers only ever reaches the provider's own address.
                    let (bytes, response) = try await session.bytes(for: request, delegate: RedirectRefuser())
                    try await Self.checkStatus(of: response, body: bytes)
                    var reader = format.makeReader()
                    for try await line in bytes.lines where line.hasPrefix("data:") {
                        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        if let text = try reader.read(payload: payload), !text.isEmpty { continuation.yield(.text(text)) }
                        if reader.isFinished { break }
                    }
                    continuation.yield(.finished(try reader.finishedTurn()))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The POST request for `conversation`.
    private func makeRequest(instructions: String, conversation: [ConversationItem], tools: [ToolDefinition]) throws -> URLRequest {
        var request = URLRequest(url: endpoint.url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.httpBody = try format.requestBody(model: model, instructions: instructions, conversation: conversation, tools: tools)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (field, value) in endpoint.headers.merging(format.formatHeaders, uniquingKeysWith: { $1 }) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    /// Throws the provider's explanation when the response isn't a success.
    private static func checkStatus(of response: URLResponse, body: URLSession.AsyncBytes) async throws {
        guard let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) else { return }
        var data = Data()
        for try await byte in body {
            guard data.count < errorBodyLimit else { break }
            data.append(byte)
        }
        throw ModelClientError.httpError(response, body: data)
    }
}
