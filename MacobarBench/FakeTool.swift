/// A real tool's double: the model sees the same name, description and parameters, but a call is only recorded and answered from the scenario.
struct FakeTool: Tool {
    /// The tool being stood in for; only its name, description, parameters and risk are read, never its `run`.
    private let real: any Tool
    /// What every call returns.
    private let output: String
    /// Where calls are recorded.
    private let log: CallLog

    /// Stands in for `real`, answering `output` and recording calls in `log`.
    init(standingInFor real: any Tool, output: String, log: CallLog) {
        self.real = real
        self.output = output
        self.log = log
    }

    /// The real tool's name.
    var name: String { real.name }
    /// The real tool's description.
    var description: String { real.description }
    /// The real tool's parameters.
    var parameters: JSONValue { real.parameters }

    /// The real tool's risk, so risky calls still go through approval.
    func risk(for input: ToolInput) -> ToolRisk {
        real.risk(for: input)
    }

    /// A fixed line; some real tools look at the screen to describe themselves.
    func activity(for input: ToolInput) -> String {
        "Calling \(name)"
    }

    /// Records the call and returns the canned output.
    func run(_ input: ToolInput) async throws -> String {
        log.record(RecordedCall(name: name, arguments: input.arguments))
        return output
    }
}
