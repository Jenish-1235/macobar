/// What counts as the model handling a scenario well.
enum Expectation: Sendable {
    /// It answers without calling any tool.
    case noTools
    /// It makes these calls in this order; other calls may come before, between or after them.
    case calls([ExpectedCall])

    /// Why `calls` miss this expectation, or nil when they meet it.
    func failure(for calls: [RecordedCall]) -> String? {
        switch self {
        case .noTools:
            return calls.isEmpty ? nil : "expected no tool calls"
        case .calls(let expected):
            var remaining = calls[...]
            for call in expected {
                guard let index = remaining.firstIndex(where: call.isMet(by:)) else { return "expected \(call.summary)" }
                remaining = remaining[remaining.index(after: index)...]
            }
            return nil
        }
    }
}
