# ChatBar
The text field pressed into the Dock gap and the glass reply sheet that rises above it only when Macie needs you.

## Files
- `ChatBarController.swift`: owns both panels and positions them from `DockGeometry`; `focusField()` brings the field forward for the Option-Space shortcut.
- `ChatBarCommand.swift`: the items in the field's right-click menu and their titles.
- `OverlayPanel.swift`: borderless panel that floats just above the Dock on every Space without activating the app.
- `ChatBarModel.swift`: draft text and the current exchange: prompt, reply, actions taken and any approval waiting; streams `ReplyEvent`s from a `ChatResponder`; `shownExchange` is the exchange only once it has an approval or has finished, and `workingStatus` ("Opening Safari…") is what the empty field shows meanwhile (tested); and reads replies aloud through `SpokenReply` when Speak Replies is on (typing, talking, a new prompt or dismissing silences it). Holds `fieldFocusRequests` and `isHearingVoice` for voice input, and `showNotice(_:)` for short messages such as why voice input stopped. Also the queue of approvals other AI apps are waiting on (`ExternalApproval`), shown oldest first once no reply is in progress (tested).
- `ChatResponder.swift`: the contract with whoever answers (Macie): `ChatResponder`, `ReplyEvent` (text, activity, approval), `ApprovalRequest` and `ApprovalDecision`.
- `ChatFieldView.swift`: the recessed capsule field with Macie, Return hint, Escape handling and the right-click menu (Change Model…, Connections…, Share Tools with AI Apps…, History…, Speak Replies, Quit); maps chat state to Macie's mood (listening while the user talks, asking while any approval waits).
- `ReplySheetView.swift`: the glass card, shown for `shownExchange`: the prompt, the actions Macie took (spinner on the current one), the streamed reply, and Allow / Always Allow / Deny when an action needs approval (with the reason when Macie asks again after reading outside content); or, for another app, "Claude Code wants to:" over the same prompt. Reports its size to its panel.
- `ChatBarStyle.swift`: every size, font, opacity and animation used above.

## Public surface
- `ChatBarController(model:onCommand:)`, `follow(_ geometry: DockGeometry?)`, `focusField()`
- `ChatBarModel(responder:spokenReply:)`, `stopSpeaking()`, `showNotice(_:)`, `requestApproval(_:from:) async -> ApprovalDecision` (for approvals asked from outside a chat, e.g. by `MCP/`)
- `protocol ChatResponder`

## Design rules
- Native first: system font, system glass, the user's accent colour. No brand colour inside the Dock.
- Macie is the one moving thing: listening while you type or hold Option-Space, hopping while working, smiling when done, flat-eyed when stuck. Everything else stays still. Reduced motion turns the hop and blink off.
- Macie works out of sight: while she works the card stays down and the empty field shows what she's doing ("Opening Safari…") with Macie hopping. The card rises only to ask for approval, and again with the finished reply or what went wrong. Everything she did is still listed on the card and in History.
- Escape once clears the draft; on an empty field it stops work in progress or collapses the reply, and returns focus. Clicking away lets her keep working. Clicking away collapses a finished reply.
- Another app's approval never replaces the user's exchange: it waits while a reply is in progress, and otherwise shows in place of a finished reply, which comes back once it's answered. Escape or Deny declines it; clicking away leaves it waiting.

## Tested by
`MacobarTests/MCPApprovalTests.swift` (the approval queue), `MacobarTests/QuietCardTests.swift` (when the card rises).

## Depends on
Dock (for `DockGeometry` only), Brand (for Macie), Speech (`SpokenReply`).
