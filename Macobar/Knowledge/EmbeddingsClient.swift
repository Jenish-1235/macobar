import Foundation

/// Turns text into vectors with an OpenAI-compatible `/embeddings` endpoint, such as LM Studio's local server.
struct EmbeddingsClient: Sendable {
    /// Most texts sent in one request.
    static let batchSize = 32
    /// Connection failures that mean the server isn't running.
    private static let unreachableCodes: Set<URLError.Code> = [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut]

    /// The server's base address, e.g. `http://localhost:1234/v1`.
    private let serverAddress: URL
    /// The embedding model to run.
    private let model: String
    /// The HTTP session; injectable for tests.
    private let session: URLSession

    /// Creates a client for `model` on the server at `serverAddress`.
    init(serverAddress: URL, model: String, session: URLSession = .shared) {
        self.serverAddress = serverAddress
        self.model = model
        self.session = session
    }

    /// One vector per text, in order, sent in batches of `batchSize`.
    func embed(_ texts: [String]) async throws -> [[Float]] {
        var vectors: [[Float]] = []
        for start in stride(from: 0, to: texts.count, by: Self.batchSize) {
            try Task.checkCancellation()
            let batch = Array(texts[start..<min(start + Self.batchSize, texts.count)])
            vectors += try await embedBatch(batch)
        }
        return vectors
    }

    /// The vectors in an embeddings reply, ordered by each item's `index`.
    static func vectors(from data: Data) throws -> [[Float]] {
        try JSONDecoder().decode(EmbeddingsReply.self, from: data).data
            .sorted { $0.index < $1.index }
            .map(\.embedding)
    }

    /// Sends one batch and checks the reply has a vector for each text.
    private func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        var request = URLRequest(url: serverAddress.appending(path: "embeddings"), timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(EmbeddingsRequest(model: model, input: texts))
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.unreachableCodes.contains(error.code) {
            throw KnowledgeError.serverUnavailable(serverAddress)
        }
        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            throw KnowledgeError.serverRejected(model: model, message: Self.errorMessage(in: data, status: response.statusCode))
        }
        guard let vectors = try? Self.vectors(from: data), vectors.count == texts.count else {
            throw KnowledgeError.unexpectedReply(model: model)
        }
        return vectors
    }

    /// The server's own explanation from an error body (`{"error": {"message": …}}` or `{"error": "…"}`), or the status code.
    private static func errorMessage(in data: Data, status: Int) -> String {
        let error = (try? JSONDecoder().decode(JSONValue.self, from: data))?["error"]
        return error?["message"]?.string ?? error?.string ?? "HTTP \(status)"
    }
}

/// The body of an embeddings request.
private struct EmbeddingsRequest: Encodable {
    /// The embedding model to run.
    let model: String
    /// The texts to embed.
    let input: [String]
}

/// The parts of an embeddings reply that are used.
private struct EmbeddingsReply: Decodable {
    /// One vector per input text.
    struct Item: Decodable {
        /// The input text's position in the request.
        let index: Int
        /// The text's vector.
        let embedding: [Float]
    }

    /// The vectors, possibly out of order.
    let data: [Item]
}
