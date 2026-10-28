/// A tool call a scenario needs, with checks on its arguments.
struct ExpectedCall: Sendable {
    /// The tool's name.
    let tool: String
    /// Checks its arguments must all pass.
    let checks: [ArgumentCheck]

    /// Expects a call to `tool` whose arguments pass every one of `checks`.
    init(_ tool: String, _ checks: ArgumentCheck...) {
        self.tool = tool
        self.checks = checks
    }

    /// Whether `call` is to this tool and passes every check.
    func isMet(by call: RecordedCall) -> Bool {
        call.name == tool && checks.allSatisfy { $0.isMet(by: call.arguments) }
    }

    /// How a failure names it, e.g. `set_timer with minutes = 5`.
    var summary: String {
        checks.isEmpty ? tool : "\(tool) with " + checks.map(\.summary).joined(separator: " and ")
    }
}
