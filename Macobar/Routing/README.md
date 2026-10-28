# Routing
Decides whether the fast model or the main model takes a prompt, and when the fast model's attempt should be handed over to the main one. Pure functions only, so the bench can measure them and the tests can pin them.

## Files
- `ModelTier.swift`: `.fast` or `.strong` (the main model).
- `Route.swift`: the router's choice for one prompt and its reason, e.g. "Short command".
- `PromptRouter.swift`: `route(_:continuing:)` picks the tier from the prompt's words; `looksLikeCommand(_:)` says whether it opens with a quick action.
- `RunOutcome.swift`: how one attempt went (tool calls, failures, whether the user declined, the answer, whether it finished, what it did).
- `Escalation.swift`: `reason(toEscalate:expectedAction:)` says why the main model should retry, or nil; `handoverPrompt(for:after:)` adds what was already done so it isn't done twice (used for either direction of handover).

## Public surface
- `PromptRouter.route(_ prompt:continuing:) -> Route`, `PromptRouter.looksLikeCommand(_:)`
- `Escalation.reason(toEscalate:expectedAction:) -> String?`, `Escalation.handoverPrompt(for:after:)`
- `Route`, `ModelTier`, `RunOutcome`

## How a prompt is routed
Checked in order; the first match wins.
1. Asks for care ("think hard", "carefully", "step by step") → main.
2. Over 40 words → main.
3. Several steps ("then", which covers "and then", "after that", or a list of two or more items) → main.
4. Needs to see the screen ("on my screen", "screenshot", "look at") → main, since local models often can't take images.
5. Holds a code block → main.
6. Points back ("it", "that", "again") while the main model answered the remembered conversation → main, so the follow-up keeps its context.
7. Opens with a command verb (open, close, quit, play, volume, timer, remind, arrange, switch, turn, set…) after filler like "please" or "can you", in 12 words or fewer → fast.
8. Asks for writing or reasoning (write, plan, research, compare, analyse, explain, code, why…) → main.
9. A question → main.
10. Six words or fewer → fast; anything else → main.

## When the fast model hands over
In order: it didn't finish (ran out of steps or the model failed) → hand over; the user declined one of its actions → keep (the main model would only ask again); two or more tool calls failed; the prompt looked like a command but it called no tool; no answer and no tool call; the answer refuses or gives up ("I can't", "I'm unable", "as an AI"). The main model gets the prompt plus a note listing actions already done.

## Gotchas
- Words are matched whole and lowercased, curly apostrophes made straight, so "screenwriter" never reads as "screen".
- A command verb wins over a reasoning word ("open VS Code" is fast), but several steps or a screen need still go to the main model.
- The two models keep separate histories (each replays turns in its own format), which is why follow-ups stick with the main model.

## Tested by
`MacobarTests/RoutingTests.swift`.

## Depends on
Nothing.
