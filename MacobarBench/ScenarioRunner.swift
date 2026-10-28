/// Runs scenarios through the real agent loop with fake tools, allowing every approval.
struct ScenarioRunner {
    /// The model under test.
    private let account: ProviderAccount
    /// A client for it, shared by every scenario.
    private let client: ModelClient
    /// Macie's real tools, offered to the model under their own names but never run.
    private let catalog: [any Tool]

    /// Prepares to run scenarios against `account`, authenticated with `credential`, offering `catalog`.
    init(account: ProviderAccount, credential: String, catalog: [any Tool]) throws {
        self.account = account
        self.client = try ModelClient(account: account, credential: credential)
        self.catalog = catalog
    }

    /// Sends the scenario's prompt to a fresh Macie and reports what she called and how long it took.
    func run(_ scenario: Scenario) async -> ScenarioResult {
        let log = CallLog()
        let tools = catalog.map { FakeTool(standingInFor: $0, output: scenario.output(of: $0.name), log: log) }
        let account = account, client = client
        let agent = Agent(connect: { (account, client) }, tools: tools, activityLog: nil)
        let clock = ContinuousClock()
        let start = clock.now
        var error: String?
        var answer = ""
        do {
            for try await event in agent.reply(to: scenario.prompt) {
                switch event {
                case .approval(let request): request.decide(.allow)
                case .text(let text): answer += text
                case .activity: break
                }
            }
        } catch let thrown {
            error = thrown.localizedDescription
        }
        let seconds = start.duration(to: clock.now) / .seconds(1)
        let calls = log.calls
        return ScenarioResult(
            name: scenario.name,
            toolsCalled: calls.map(\.name),
            seconds: seconds,
            failure: error ?? scenario.expectation.failure(for: calls),
            answer: answer
        )
    }
}
