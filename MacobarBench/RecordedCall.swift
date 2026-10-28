/// A tool call the model made during a scenario, as the fake tool received it.
struct RecordedCall: Sendable {
    /// The tool's name.
    let name: String
    /// The decoded JSON arguments.
    let arguments: [String: JSONValue]
}
