import Foundation
import Testing

/// Answers each request with the canned HTTP response for its host.
final class HostStubURLProtocol: URLProtocol {
    /// Status and body returned for each host.
    nonisolated(unsafe) static var responses: [String: (status: Int, body: String)] = [:]

    /// Handles every request.
    override class func canInit(with request: URLRequest) -> Bool { true }

    /// Leaves requests unchanged.
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// Replies with the host's canned response.
    override func startLoading() {
        guard let url = request.url, let canned = Self.responses[url.host() ?? ""],
              let response = HTTPURLResponse(url: url, statusCode: canned.status, httpVersion: "HTTP/1.1", headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(canned.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    /// Nothing to stop; responses are delivered at once.
    override func stopLoading() {}
}

/// Verifies which model answers when the main one is rate-limited.
struct ModelFallbackTests {
    /// The main model, on Claude.
    private let main = ProviderAccount(kind: .claude, model: "claude-opus-5-5")
    /// The fast model, on a local server.
    private let fast = ProviderAccount(kind: .local, model: "qwen", setting: "http://localhost:1234/v1")

    /// A client for `account` whose requests go to `HostStubURLProtocol`.
    private func client(for account: ProviderAccount) throws -> ModelClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HostStubURLProtocol.self]
        return try ModelClient(account: account, credential: "secret", session: URLSession(configuration: configuration))
    }

    @Test("A prompt for the main model goes to the fast one when the main model's rate limit runs out")
    func rateLimitedMainFallsBackToFast() async throws {
        HostStubURLProtocol.responses = [
            "api.anthropic.com": (429, #"{"type":"error","error":{"type":"rate_limit_error","message":"Tokens per minute exceeded. Please try again in 120s."}}"#),
            "localhost": (200, ChatCompletionsFormatTests.textStream),
        ]
        let (main, fast) = (main, fast)
        let mainClient = try client(for: main), fastClient = try client(for: fast)
        let agent = Agent(connect: { (main, mainClient) }, connectFast: { (fast, fastClient) }, tools: [], activityLog: nil)
        var text = "", activities: [String] = []
        for try await event in agent.reply(to: "What's on my screen right now?") {
            switch event {
            case .text(let more): text += more
            case .activity(let activity): activities.append(activity)
            default: break
            }
        }
        #expect(text == "Two meetings.")
        #expect(activities.contains("claude-opus-5-5 is rate-limited; using the fast model"))
    }
}
