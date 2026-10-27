/// Stand-in reply source until the agent exists; streams a fixed note word by word.
struct PlaceholderResponder: ChatResponder {
    /// The note every prompt receives for now.
    private static let note = "The bar works. The agent that carries out your request arrives in the next build."

    /// Streams the note with a short delay between words, like a real model reply.
    func reply(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for word in Self.note.split(separator: " ") {
                        try await Task.sleep(for: .milliseconds(45))
                        continuation.yield(word + " ")
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
