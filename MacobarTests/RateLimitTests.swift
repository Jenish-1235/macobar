import Foundation
import Testing

/// Verifies that short rate limits are told apart from other errors, with the suggested wait.
struct RateLimitTests {
    /// An HTTP response with `status` and `headers`.
    private func response(_ status: Int, headers: [String: String] = [:]) throws -> HTTPURLResponse {
        try #require(HTTPURLResponse(url: URL(filePath: "/"), statusCode: status, httpVersion: nil, headerFields: headers))
    }

    @Test("A tokens-per-minute error in the stream is a rate limit with the wait from its message")
    func streamRateLimit() {
        var reader = ResponsesReplyReader()
        let payload = #"{"type":"error","error":{"code":"rate_limit_exceeded","message":"Rate limit reached for gpt-6.1 on tokens per min (TPM). Please try again in 1.5s."}}"#
        #expect(throws: ModelClientError.rateLimited(
            message: "Rate limit reached for gpt-6.1 on tokens per min (TPM). Please try again in 1.5s. (rate_limit_exceeded)",
            retryAfter: 1.5
        )) { try reader.read(payload: payload) }
    }

    @Test("An HTTP 429 rate limit takes its wait from the retry-after header")
    func httpRateLimit() throws {
        let body = Data(#"{"type":"error","error":{"type":"rate_limit_error","message":"Number of tokens per minute exceeded."}}"#.utf8)
        let error = ModelClientError.httpError(try response(429, headers: ["retry-after": "12"]), body: body)
        #expect(error == .rateLimited(message: "Number of tokens per minute exceeded.", retryAfter: 12))
    }

    @Test("Running out of credit or plan usage is not retried")
    func quotaIsNotARateLimit() throws {
        let body = Data(#"{"error":{"code":"insufficient_quota","message":"You exceeded your current quota."}}"#.utf8)
        #expect(ModelClientError.httpError(try response(429), body: body) == .rejected(status: 429, message: "You exceeded your current quota."))
    }

    @Test("Waits are read in seconds or milliseconds", arguments: [
        ("Please try again in 20s.", 20.0),
        ("Please try again in 350ms.", 0.35),
        ("Slow down.", nil),
    ] as [(String, Double?)])
    func retryDelay(message: String, seconds: Double?) {
        #expect(ModelClientError.retryDelay(mentionedIn: message) == seconds)
    }
}
