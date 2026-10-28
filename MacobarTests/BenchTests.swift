import Testing

/// A recorded call to `name` with `arguments`.
private func call(_ name: String, _ arguments: [String: JSONValue] = [:]) -> RecordedCall {
    RecordedCall(name: name, arguments: arguments)
}

/// Verifies how the bench checks a call's arguments.
struct ArgumentCheckTests {
    @Test("contains ignores case and matches any item of a list")
    func containsIgnoresCaseAndReadsLists() {
        #expect(ArgumentCheck.contains("name", "safari").isMet(by: ["name": "Safari Technology Preview"]))
        #expect(ArgumentCheck.contains("to", "alex@").isMet(by: ["to": ["sam@example.com", "Alex@example.com"]]))
        #expect(!ArgumentCheck.contains("name", "Safari").isMet(by: ["name": "Chrome"]))
        #expect(!ArgumentCheck.contains("name", "Safari").isMet(by: [:]))
    }

    @Test("equals needs the whole string, ignoring case")
    func equalsNeedsWholeString() {
        #expect(ArgumentCheck.equals("position", "left_half").isMet(by: ["position": "LEFT_HALF"]))
        #expect(!ArgumentCheck.equals("position", "left_half").isMet(by: ["position": "left_half_top"]))
    }

    @Test("number needs a JSON number, not a numeric string")
    func numberNeedsJSONNumber() {
        #expect(ArgumentCheck.number("minutes", 5).isMet(by: ["minutes": 5]))
        #expect(!ArgumentCheck.number("minutes", 5).isMet(by: ["minutes": 6]))
        #expect(!ArgumentCheck.number("minutes", 5).isMet(by: ["minutes": "5"]))
    }

    @Test("an expected call names its tool and every check")
    func expectedCallSummary() {
        #expect(ExpectedCall("set_timer", .number("minutes", 5)).summary == "set_timer with minutes = 5")
        #expect(ExpectedCall("list_events").summary == "list_events")
    }
}

/// Verifies whether a scenario's calls meet its expectation.
struct ExpectationTests {
    @Test("no tools passes only when nothing was called")
    func noTools() {
        #expect(Expectation.noTools.failure(for: []) == nil)
        #expect(Expectation.noTools.failure(for: [call("open_app")]) == "expected no tool calls")
    }

    @Test("expected calls must come in order, with other calls allowed around them")
    func callsInOrder() {
        let expectation = Expectation.calls([ExpectedCall("get_frontmost_context"), ExpectedCall("read_window_text")])
        #expect(expectation.failure(for: [call("list_running_apps"), call("get_frontmost_context"), call("read_window_text")]) == nil)
        #expect(expectation.failure(for: [call("read_window_text"), call("get_frontmost_context")]) == "expected read_window_text")
    }

    @Test("a call to the right tool with wrong arguments doesn't count")
    func wrongArguments() {
        let expectation = Expectation.calls([ExpectedCall("set_timer", .number("minutes", 5))])
        #expect(expectation.failure(for: [call("set_timer", ["minutes": 50])]) == "expected set_timer with minutes = 5")
        #expect(expectation.failure(for: [call("set_timer", ["minutes": 50]), call("set_timer", ["minutes": 5])]) == nil)
    }

    @Test("one call can't satisfy two expected calls")
    func oneCallPerExpectation() {
        let expectation = Expectation.calls([ExpectedCall("search_files"), ExpectedCall("search_files")])
        #expect(expectation.failure(for: [call("search_files")]) == "expected search_files")
    }

    @Test("every scenario has its own name")
    func scenarioNamesAreUnique() {
        #expect(Set(Scenario.all.map(\.name)).count == Scenario.all.count)
    }
}

/// Verifies reading the command line.
struct BenchOptionsTests {
    @Test("a local model needs no key and defaults to LM Studio's address")
    func localDefaults() throws {
        let options = try BenchOptions(arguments: ["--provider", "local", "--model", "qwen3-8b"], environment: [:])
        #expect(options.account == ProviderAccount(kind: .local, model: "qwen3-8b", setting: "http://localhost:1234/v1"))
        #expect(options.credential == "")
        #expect(options.only == nil)
    }

    @Test("a hosted provider takes its key from MACOBAR_API_KEY")
    func hostedKey() throws {
        let options = try BenchOptions(arguments: ["--provider", "openRouter", "--model", "x/y", "--only", "timer"], environment: ["MACOBAR_API_KEY": "k"])
        #expect(options.account == ProviderAccount(kind: .openRouter, model: "x/y", setting: nil))
        #expect(options.credential == "k")
        #expect(options.only == "timer")
    }

    @Test("mistakes are refused", arguments: [
        ["--provider", "gemini", "--model", "m"],
        ["--provider", "nope", "--model", "m"],
        ["--provider", "local"],
        ["--provider", "local", "--model"],
        ["--provider", "local", "--model", "m", "--verbose", "yes"],
    ])
    func mistakes(arguments: [String]) {
        #expect(throws: BenchUsageError.self) { try BenchOptions(arguments: arguments, environment: [:]) }
    }
}

/// Verifies the printed results.
struct BenchReportTests {
    @Test("the summary counts passes and takes the median time")
    func summary() {
        let results = [
            ScenarioResult(name: "a", toolsCalled: [], seconds: 1, failure: nil),
            ScenarioResult(name: "b", toolsCalled: [], seconds: 4, failure: "expected open_app"),
            ScenarioResult(name: "c", toolsCalled: [], seconds: 2, failure: nil),
            ScenarioResult(name: "d", toolsCalled: [], seconds: 9, failure: nil),
        ]
        let summary = BenchSummary(results: results)
        #expect(summary.passedCount == 3)
        #expect(summary.passRate == 75)
        #expect(summary.medianSeconds == 3)
        #expect(summary.totalSeconds == 16)
    }

    @Test("an empty run has a zero summary")
    func emptySummary() {
        #expect(BenchSummary(results: []).line == "Passed 0 of 0 (0%). Median 0.0s, total 0.0s.")
    }

    @Test("a result line shows the verdict, tools and failure")
    func resultLine() {
        let line = ScenarioResult(name: "timer", toolsCalled: ["set_timer"], seconds: 4.25, failure: "expected set_timer with minutes = 5").line
        #expect(line.hasPrefix("FAIL  timer "))
        #expect(line.hasSuffix("set_timer  (expected set_timer with minutes = 5)"))
    }
}
