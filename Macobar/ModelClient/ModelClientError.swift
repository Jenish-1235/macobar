import Foundation

/// Why a reply couldn't be produced.
enum ModelClientError: LocalizedError, Equatable {
    /// The provider refused the request with an HTTP error, optionally explaining why.
    case rejected(status: Int, message: String?)
    /// The provider failed partway through the reply.
    case failed(String)
    /// The model declined to answer.
    case declined

    /// What to tell the user.
    var errorDescription: String? {
        switch self {
        case .rejected(_, let message?): message
        case .rejected(let status, nil): Self.summary(of: status)
        case .failed(let message): message
        case .declined: "The model declined to answer this one."
        }
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

/// The `{"message": …}` object providers put inside an `error` field.
struct ProviderErrorDetail: Decodable, Equatable {
    /// Human-readable explanation.
    let message: String?
}

/// An HTTP error body: `{"error": {"message": …}}`, or a one-element array of that (Gemini).
struct ProviderErrorBody: Decodable {
    /// The error inside the body.
    let error: ProviderErrorDetail?

    /// The explanation inside `body`, if it has one.
    static func message(in body: Data) -> String? {
        let decoder = JSONDecoder()
        let single = try? decoder.decode(Self.self, from: body)
        let first = (try? decoder.decode([Self].self, from: body))?.first
        return (single ?? first)?.error?.message
    }
}
