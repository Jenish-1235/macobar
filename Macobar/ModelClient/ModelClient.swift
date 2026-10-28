import Foundation

/// Sends a conversation to the active provider and streams the reply back as text.
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

    /// Streams the model's reply to `conversation` as text fragments.
    func streamReply(instructions: String, conversation: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(instructions: instructions, conversation: conversation)
                    let (bytes, response) = try await session.bytes(for: request)
                    try await Self.checkStatus(of: response, body: bytes)
                    for try await line in bytes.lines {
                        switch try format.read(line: line) {
                        case .text(let text): continuation.yield(text)
                        case .finished: return continuation.finish()
                        case .ignored: continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The POST request for `conversation`.
    private func makeRequest(instructions: String, conversation: [ChatMessage]) throws -> URLRequest {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = "POST"
        request.httpBody = try format.requestBody(model: model, instructions: instructions, conversation: conversation)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (field, value) in endpoint.headers.merging(format.formatHeaders, uniquingKeysWith: { $1 }) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    /// Throws the provider's explanation when the response isn't a success.
    private static func checkStatus(of response: URLResponse, body: URLSession.AsyncBytes) async throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) else { return }
        var data = Data()
        for try await byte in body {
            guard data.count < errorBodyLimit else { break }
            data.append(byte)
        }
        throw ModelClientError.rejected(status: status, message: ProviderErrorBody.message(in: data))
    }
}
