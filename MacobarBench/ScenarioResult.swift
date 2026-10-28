import Foundation

/// How the model did on one scenario.
struct ScenarioResult: Sendable {
    /// Width the scenario name is padded to, so columns line up.
    private static let nameWidth = 20

    /// The scenario's name.
    let name: String
    /// Names of the tools called, in order.
    let toolsCalled: [String]
    /// Seconds from prompt to finished reply.
    let seconds: Double
    /// Why it failed, or nil when it passed.
    let failure: String?
    /// What the model finally said, shown under a failure so it can be understood.
    var answer = ""

    /// Whether it passed.
    var passed: Bool { failure == nil }

    /// One printed line, e.g. `PASS  timer                4.2s  set_timer`.
    var line: String {
        let tools = toolsCalled.isEmpty ? "no tools" : toolsCalled.joined(separator: ", ")
        let paddedName = name.padding(toLength: max(name.count, Self.nameWidth), withPad: " ", startingAt: 0)
        let columns = "\(passed ? "PASS" : "FAIL")  \(paddedName) \(String(format: "%5.1fs", seconds))  \(tools)"
        guard let failure else { return columns }
        let said = answer.split(whereSeparator: \.isNewline).joined(separator: " ").prefix(300)
        return "\(columns)  (\(failure))" + (said.isEmpty ? "" : "\n      said: \(said)")
    }
}
