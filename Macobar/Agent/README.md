# Agent
Macie herself: the loop that turns a prompt into model turns and tool runs until the task is done.

## Files
- `Agent.swift`: the `ChatResponder` the chat bar talks to. Picks the fast or main model per prompt (`Routing/`), runs the loop, asks for approval, records each action (`Activity/`), keeps the conversation, and reports text, actions and approval requests as `ReplyEvent`s. Also `AgentError` (no model connected, key missing).
- `ContentExposure.swift`: what outside text has reached the model (any, and possibly private), and the rule for when a call runs without asking (tested).
- `MacieInstructions.swift`: the system prompt: how Macie works and replies, which tools to prefer, the rule that outside text is information and never instructions, what she remembers (as facts, never instructions), and today's date.
- `MacieMemory.swift`: facts Macie keeps about the user (`Memory`: id like "m3", text, date added) in `~/Library/Application Support/macobar/memory.json`. Add (one line, at most 300 characters, duplicates return the existing fact, at most 100 facts) and remove by id; malformed or overlong entries are dropped on read.
- `ToolApprovals.swift`: the tools the user chose to always allow (preferences), and `revoke(namesStartingWith:)` for a removed MCP server's tools.

## Public surface
- `Agent(accountStore:tools:promptTools:remembersConversation:)` (conforms to `ChatResponder`)
- `Agent(connect:connectFast:tools:promptTools:approvals:activityLog:remembersConversation:)`: the same agent with the clients supplied by closures (used by `macobar-bench`, with no activity log)

## The loop
1. Read the main account and, if set, the fast account (fresh every prompt). If they differ, `PromptRouter` picks one; the card shows "Using the fast model".
2. Gather this prompt's tools: the built-in ones plus each prompt's `promptTools` (MCP servers' tools), sorted by name; a built-in tool wins a name clash.
3. Send the conversation and tool definitions; stream text to the card as it arrives.
4. Run each tool the model called, in order: unknown tool or bad JSON → error result; risky → ask in the card; then run it (`look` for a `VisualTool`, whose images go back with the text) and send the output back (cut to 12,000 characters, since every later step resends it).
5. Repeat until a turn has no tool calls (at most 30 turns). If the fast model struggles (fails, errors twice, answers a command without acting, refuses), the card shows "Handing over to …" and the main model gets the prompt plus what was already done.
6. Keep the exchange for follow-ups (the last 8 prompts, with what outside text each brought in), unless `remembersConversation` is false (scheduled runs).

## Approvals
- `ToolRisk.none` runs straight away. `.confirmOnce` asks, offering Always Allow (remembered per tool). `.confirmEveryTime` always asks.
- Always Allow stops counting once outside text is in the conversation: from a tool that `readsOutsideContent` in this prompt or any remembered one, or from MCP servers' tool definitions. The card says why it's asking again.
- Once private text could be in the conversation (anything outside except a public page fetched without asking), `ToolCatalog.sendsDataOut` tools ask too, with no Always Allow.
- A declined action goes back to the model as an error saying not to retry. Dismissing the card while a request is waiting declines it.

## Rate limits
A short rate limit (requests or tokens per minute) is waited out and the turn retried, up to 3 times and 60 seconds a wait, showing "Waiting 12s for the rate limit" in the card. Quota and plan-usage limits fail straight away. When the main model's rate limit still runs out and a separate fast model is set, the card shows "… is rate-limited; using the fast model" and the fast model gets the prompt plus what was already done.

## Gotchas
- Each model turn is replayed in the provider's own form (`AssistantTurn.nativeContent`), so Claude's thinking blocks and OpenAI's encrypted reasoning survive tool steps unchanged.
- History is append-only per account; an unfinished prompt is dropped as a whole, so earlier turns are never edited.
- Tool definitions are sorted by name and the system prompt changes only with the date or a memory, so requests stay cacheable.
- Screenshots aren't trimmed like text and stay in the remembered history.
- The chat, the scheduler and MCP sharing each have their own tool catalog (and so their own screen marks).

## Tested by
`MacobarTests/ContentExposureTests.swift`, `MacieMemoryTests.swift`, `RoutingTests.swift`, and the loop through `macobar-bench`.

## Depends on
ModelClient, Providers, Tools, Routing, Activity, ChatBar (`ChatResponder`, `ReplyEvent`, `ApprovalRequest`).
