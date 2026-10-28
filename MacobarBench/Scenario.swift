/// One task for the model: a prompt, what its tools answer, and what it should call.
struct Scenario: Sendable {
    /// Short kebab-case name, used by `--only`.
    let name: String
    /// What the user types into the Dock.
    let prompt: String
    /// What each tool returns, by tool name; tools not listed return "OK".
    let outputs: [String: String]
    /// What counts as success.
    let expectation: Expectation

    /// Creates a scenario named `name` for `prompt`.
    init(_ name: String, prompt: String, outputs: [String: String] = [:], expects expectation: Expectation) {
        self.name = name
        self.prompt = prompt
        self.outputs = outputs
        self.expectation = expectation
    }

    /// What the fake `tool` returns in this scenario.
    func output(of tool: String) -> String {
        outputs[tool] ?? "OK"
    }
}
