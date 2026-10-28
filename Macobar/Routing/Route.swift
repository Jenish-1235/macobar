/// The router's choice for one prompt, with why it was made.
struct Route: Sendable, Equatable {
    /// The model that takes the prompt.
    let tier: ModelTier
    /// Why, in a few words, e.g. "Short command".
    let reason: String
}
