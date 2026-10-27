/// Anything that can answer a prompt typed into the chat bar, streaming the reply in fragments.
protocol ChatResponder: Sendable {
    /// Streams the reply to `prompt` as text fragments.
    func reply(to prompt: String) -> AsyncThrowingStream<String, Error>
}
