import Foundation

/// Why knowledge search couldn't read or embed text, in words that say how to fix it.
enum KnowledgeError: LocalizedError, Equatable {
    /// Nothing answered at the embeddings server's address.
    case serverUnavailable(URL)
    /// The server answered with an error, e.g. no embedding model loaded.
    case serverRejected(model: String, message: String)
    /// The server's reply didn't hold one vector per text, or the vectors changed size.
    case unexpectedReply(model: String)
    /// A folder to index is missing or macobar isn't allowed to read it.
    case folderUnreadable(URL)

    /// The message, for `localizedDescription`.
    var errorDescription: String? {
        switch self {
        case .serverUnavailable(let address):
            "Nothing answered at \(address.absoluteString). Start LM Studio's server and load an embedding model, then try again."
        case .serverRejected(let model, let message):
            "The embeddings server refused the request (\(message)). Load the embedding model \"\(model)\" in LM Studio, then try again."
        case .unexpectedReply(let model):
            "The embeddings server's reply didn't match the text sent. Check that \"\(model)\" is an embedding model."
        case .folderUnreadable(let folder):
            "Couldn't read \(folder.path). If it exists, allow macobar in System Settings → Privacy & Security → Files and Folders; otherwise index other folders."
        }
    }
}
