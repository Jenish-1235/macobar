import Foundation

/// Why a reply couldn't be produced.
enum ModelClientError: LocalizedError, Equatable {
    /// The provider refused the request with an HTTP error, optionally explaining why.
    case rejected(status: Int, message: String?)
    /// The provider failed partway through the reply.
    case failed(String)
    /// The model declined to answer.
    case declined
    /// A short-term rate limit (requests or tokens per minute); worth retrying after `retryAfter` seconds when known.
    case rateLimited(message: String, retryAfter: Double?)

    /// What to tell the user.
    var errorDescription: String? {
        switch self {
        case .rejected(_, let message?): message
        case .rejected(let status, nil): Self.summary(of: status)
        case .failed(let message): message
        case .declined: "The model declined to answer this one."
        case .rateLimited(let message, _): message
        }
    }

    /// An error event in the stream: its message and code when present, otherwise the raw event so nothing is hidden.
    static func streamError(message: String?, code: String?, payload: String) -> ModelClientError {
        if let code, code.contains("rate_limit") {
            let text = message ?? "The provider's rate limit was reached."
            return .rateLimited(message: "\(text) (\(code))", retryAfter: retryDelay(mentionedIn: text))
        }
        switch (message, code) {
        case (let message?, let code?): return .failed("\(message) (\(code))")
        case (let message?, nil): return .failed(message)
        case (nil, _): return .failed("The provider reported an error: \(payload.prefix(400))")
        }
    }

    /// An HTTP error: rate limits (by error code) become `rateLimited` with the wait from headers or message; anything else, `rejected`.
    static func httpError(_ response: HTTPURLResponse, body: Data) -> ModelClientError {
        let detail = ProviderErrorBody.detail(in: body)
        guard response.statusCode == 429, let code = detail?.code ?? detail?.type, code.contains("rate_limit") else {
            return .rejected(status: response.statusCode, message: detail?.message)
        }
        let message = detail?.message ?? "The provider's rate limit was reached."
        let delay = (response.value(forHTTPHeaderField: "retry-after-ms").flatMap(Double.init)).map { $0 / 1000 }
            ?? response.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
            ?? retryDelay(mentionedIn: message)
        // A wait that's negative, infinite or not a number can't be slept through or shown, so it counts as unknown.
        return .rateLimited(message: message, retryAfter: delay.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil })
    }

    /// The wait in seconds a message suggests, e.g. "Please try again in 1.5s" or "in 300ms".
    static func retryDelay(mentionedIn message: String) -> Double? {
        guard let match = message.firstMatch(of: /try again in (\d+(?:\.\d+)?)\s*(ms|s)\b/) else { return nil }
        guard let amount = Double(match.1), amount.isFinite else { return nil }
        return match.2 == "ms" ? amount / 1000 : amount
    }

    /// A plain explanation of an HTTP status the provider gave no message for.
    private static func summary(of status: Int) -> String {
        switch status {
        case 401, 403: "The provider didn't accept your key."
        case 404: "The provider couldn't find that model."
        case 429: "The provider's rate limit was reached. Try again shortly."
        case 500...: "The provider is having trouble (HTTP \(status))."
        default: "The provider rejected the request (HTTP \(status))."
        }
    }
}

/// The `{"message": …, "code": …}` object providers put inside an `error` field.
struct ProviderErrorDetail: Decodable, Equatable {
    /// Human-readable explanation.
    let message: String?
    /// Machine-readable code (OpenAI), e.g. `rate_limit_exceeded`.
    let code: String?
    /// Machine-readable type (Anthropic), e.g. `rate_limit_error`.
    let type: String?

    /// Reads each field leniently, since some providers send numeric codes.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try? container.decode(String.self, forKey: .message)
        code = try? container.decode(String.self, forKey: .code)
        type = try? container.decode(String.self, forKey: .type)
    }

    /// The fields read.
    private enum CodingKeys: String, CodingKey {
        case message, code, type
    }
}

/// An HTTP error body: `{"error": {"message": …}}`, or a one-element array of that (Gemini).
struct ProviderErrorBody: Decodable {
    /// The error inside the body.
    let error: ProviderErrorDetail?

    /// The error inside `body`, if it has one.
    static func detail(in body: Data) -> ProviderErrorDetail? {
        let decoder = JSONDecoder()
        let single = try? decoder.decode(Self.self, from: body)
        let first = (try? decoder.decode([Self].self, from: body))?.first
        return (single ?? first)?.error
    }
}
