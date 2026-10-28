# MacobarBench
`macobar-bench`, a command-line tool that measures how well a model drives Macie's tools. The model runs the real agent loop with stand-in tools, so nothing on the Mac is opened, changed or sent.

## Run it
Build the `macobar-bench` scheme in Xcode (or `xcodebuild -scheme macobar-bench build`), then run the binary from the build folder.

```sh
# LM Studio: load a model and start its local server, then:
macobar-bench --provider local --model qwen3-8b
macobar-bench --provider local --model qwen3-8b --address http://localhost:1234/v1 --only timer

# Hosted providers read the key from MACOBAR_API_KEY:
MACOBAR_API_KEY=<key> macobar-bench --provider openRouter --model <model-id>
MACOBAR_API_KEY=<key> macobar-bench --provider claude --model claude-opus-5-5
```

- `--provider`: a `ProviderKind` raw value: `claude`, `bedrock`, `openAI`, `chatGPT`, `gemini`, `azureOpenAI`, `openRouter`, `openCodeZen`, `local`.
- `--model`: the model ID (optional for Claude and Bedrock, which have a default).
- `--address`: the provider's extra setting: the server address for `local` (default `http://localhost:1234/v1`; Ollama is `http://localhost:11434/v1`), the resource name for Azure, the region for Bedrock.
- `--only <name>`: run one scenario.

It prints one line per scenario and a summary, and always exits 0, since it's a measurement:

```
PASS  timer                  2.4s  set_timer
FAIL  this-page              6.1s  get_browser_tab, fetch_web_page  (expected get_frontmost_context)
Passed 14 of 16 (88%). Median 3.0s, total 51.7s.
```

## Files
- `MacobarBench.swift`: the `@main` entry: reads options, runs scenarios one at a time, prints results.
- `BenchOptions.swift`: reads the command line and `MACOBAR_API_KEY` into a `ProviderAccount` (tested). Also `BenchUsageError`.
- `Scenario.swift`: one task: a name, the prompt, each tool's canned output ("OK" when not given) and the expectation.
- `Scenarios.swift`: the 17 scenarios, as Swift data.
- `Expectation.swift`, `ExpectedCall.swift`, `ArgumentCheck.swift`: what counts as a pass (tested).
- `FakeTool.swift`: stands in for a real tool: same name, description, parameters and risk, but `run` only records the call and returns the canned output.
- `RecordedCall.swift`, `CallLog.swift`: the calls made in one scenario.
- `ScenarioRunner.swift`: runs one scenario through a fresh `Agent` built with `Agent(connect:tools:)`, allowing every approval, and times it.
- `ScenarioResult.swift`, `BenchSummary.swift`: the printed line per scenario and the summary: pass rate, median and total seconds (tested).

## Scoring
- `.noTools`: passes when the model answers without calling anything.
- `.calls([...])`: each expected call must appear in order, each matched by a later call than the last; other calls may come before, between or after. A call matches when it names the tool and passes every `ArgumentCheck`: `contains` (ignoring case; any item of a list), `equals` (whole string, ignoring case) or `number` (a JSON number, not a numeric string).
- An error from the model (rejected, rate limited past the retries, 30 steps without finishing) fails the scenario with that message.

## Adding a scenario
Add a `Scenario` to `Scenarios.swift` with a unique kebab-case name, the prompt, canned outputs for the tools it should use (written like the real tool's output), and its expectation. Keep checks loose enough that any good answer passes (e.g. `contains("due", "09:00")`, not a full date).

## Gotchas
- Every tool in `ToolCatalog.all` is offered with its real description, so the bench measures exactly what Macie sees. Their sources compile into the bench but `run` is never called; `activity` is replaced too, since some tools read the screen to describe themselves.
- The target compiles all of `Macobar/Tools`, catalogued or not, so every module a file there uses (e.g. `Activity`, `Knowledge`, `Guide`, `Overlay`) must be in the target's sources in `project.yml`.
- Risky calls still raise approval requests; the bench answers each with Allow, never Always Allow, so nothing is saved.
- The system prompt is Macie's real one, including today's date and any facts in the user's `memory.json`, so results can shift slightly between days and Macs.
- Each scenario starts a fresh `Agent`, so no conversation carries over. Scenarios run one at a time so timings don't compete.

## Tested by
`MacobarTests/BenchTests.swift`.

## Depends on
Agent, Tools (`ToolCatalog`), ModelClient, Providers, ChatBar (`ReplyEvent`, `ApprovalRequest`).
