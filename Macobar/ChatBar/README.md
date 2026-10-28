# ChatBar
The text field pressed into the Dock gap and the glass reply sheet that rises above it.

## Files
- `ChatBarController.swift`: owns both panels and positions them from `DockGeometry`.
- `OverlayPanel.swift`: borderless panel that floats just above the Dock on every Space without activating the app.
- `ChatBarModel.swift`: draft text and the current prompt/reply exchange; streams replies from a `ChatResponder`.
- `ChatResponder.swift`: protocol for anything that answers a prompt (the model now, the agent later).
- `ChatFieldView.swift`: the recessed capsule field with Macie, Return hint, Escape handling and the Change Model… / Quit menu; maps chat state to Macie's mood.
- `ReplySheetView.swift`: the glass card showing the prompt and streamed reply; reports its size to its panel.
- `ChatBarStyle.swift`: every size, font, opacity and animation used above.

## Public surface
- `ChatBarController(model:onChangeModel:onQuit:)`, `follow(_ geometry: DockGeometry?)`
- `ChatBarModel(responder:)`
- `protocol ChatResponder`

## Design rules
- Native first: system font, system glass, the user's accent colour. No brand colour inside the Dock.
- Macie is the one moving thing: listening while you type, hopping while working, smiling when done, flat-eyed when stuck. Everything else stays still. Reduced motion turns the hop and blink off.
- Escape once clears the draft, twice collapses the reply and returns focus. Clicking away collapses a finished reply.

## Depends on
Dock (for `DockGeometry` only), Brand (for Macie).
