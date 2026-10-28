import Foundation
import Testing

/// Answers every request with a canned HTTP response and remembers the request.
final class StubURLProtocol: URLProtocol {
    /// Status and body returned to the next request.
    nonisolated(unsafe) static var cannedResponse = (status: 200, body: "")
    /// The last request received.
    nonisolated(unsafe) static var lastRequest: URLRequest?

    /// Handles every request.
    override class func canInit(with request: URLRequest) -> Bool { true }

    /// Leaves requests unchanged.
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// Records the request and replies with the canned response.
    override func startLoading() {
        Self.lastRequest = request
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: Self.cannedResponse.status, httpVersion: "HTTP/1.1", headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.cannedResponse.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    /// Nothing to stop; responses are delivered at once.
    override func stopLoading() {}
}

/// Runs `ModelClient` end to end against stubbed HTTP responses.
@Suite(.serialized)
struct ModelClientTests {
    /// A Claude client whose requests go to `StubURLProtocol`.
    private func makeClient(kind: ProviderKind = .claude) throws -> ModelClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let account = ProviderAccount(kind: kind, model: kind.defaultModel ?? "test-model")
        return try ModelClient(account: account, credential: "secret", session: URLSession(configuration: configuration))
    }

    /// Collects the whole reply.
    private func reply(from client: ModelClient) async throws -> String {
        var reply = ""
        for try await fragment in client.streamReply(instructions: "Be brief.", conversation: sampleConversation) {
            reply += fragment
        }
        return reply
    }

    @Test("A streamed reply arrives as text, sent with the provider's headers")
    func streamedReply() async throws {
        StubURLProtocol.cannedResponse = (200, AnthropicMessagesFormatTests.recordedStream)
        #expect(try await reply(from: makeClient()) == "Hello there.")
        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "secret")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("An HTTP error surfaces the provider's own explanation")
    func rejectedWithMessage() async throws {
        StubURLProtocol.cannedResponse = (401, #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)
        await #expect(throws: ModelClientError.rejected(status: 401, message: "invalid x-api-key")) {
            try await reply(from: makeClient())
        }
    }

    @Test("Gemini's array-shaped error body is understood")
    func rejectedWithArrayBody() async throws {
        StubURLProtocol.cannedResponse = (400, #"[{"error":{"code":400,"message":"API key not valid.","status":"INVALID_ARGUMENT"}}]"#)
        await #expect(throws: ModelClientError.rejected(status: 400, message: "API key not valid.")) {
            try await reply(from: makeClient(kind: .gemini))
        }
    }

    @Test("An HTTP error without a body still explains itself")
    func rejectedWithoutMessage() {
        #expect(ModelClientError.rejected(status: 401, message: nil).errorDescription == "The provider didn't accept your key.")
    }
}
