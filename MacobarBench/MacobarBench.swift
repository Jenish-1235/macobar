import Foundation

/// Measures how well a model drives Macie's tools, using fake tools so nothing on the Mac changes.
@main
enum MacobarBench {
    /// Runs the chosen scenarios one at a time, printing a line for each and a summary; exits 0 either way, since it's a measurement.
    static func main() async {
        do {
            let options = try BenchOptions(arguments: Array(CommandLine.arguments.dropFirst()), environment: ProcessInfo.processInfo.environment)
            let scenarios = Scenario.all.filter { options.only == nil || $0.name == options.only }
            guard !scenarios.isEmpty else {
                throw BenchUsageError("No scenario is named \(options.only ?? ""). Choose one of: \(Scenario.all.map(\.name).joined(separator: ", ")).")
            }
            let catalog = await MainActor.run { ToolCatalog(overlay: ScreenOverlay(), diagrams: DiagramWindow(), knowledge: KnowledgeIndexer()).all }
            let runner = try ScenarioRunner(account: options.account, credential: options.credential, catalog: catalog)
            print("Measuring \(options.account.model) on \(options.account.kind.displayName) with \(scenarios.count) scenarios.")
            var results: [ScenarioResult] = []
            for scenario in scenarios {
                let result = await runner.run(scenario)
                print(result.line)
                results.append(result)
            }
            print(BenchSummary(results: results).line)
        } catch {
            print(error.localizedDescription)
            print(BenchOptions.usage)
        }
    }
}
