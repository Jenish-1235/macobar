/// Which of the two connected models takes a prompt.
enum ModelTier: Sendable, Equatable {
    /// The quick, cheap model, often running on this Mac.
    case fast
    /// The main model, for anything that needs reasoning or writing.
    case strong
}
