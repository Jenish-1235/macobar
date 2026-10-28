# Speech
Macie reads her replies aloud as they stream in, one sentence at a time. Off by default.

## Files
- `SpokenReply.swift`: `begin` starts a reply; takes its text as it arrives (`append`), speaks each sentence as soon as it's complete with `AVSpeechSynthesizer` (queued in order), and speaks the rest at `finish`. `stop` goes quiet at once and keeps the rest of that reply silent. `isOn` is the saved switch.
- `SentenceSplitter.swift`: cuts streamed text into sentences at `.`, `!`, `?` (plus closing quotes, brackets, `*`, `_`) followed by a space, and at new lines (tested). Keeps a code block whole until it closes.
- `SpeakableText.swift`: what's worth saying in a sentence: drops code blocks, says URLs as "link", reads a Markdown link's text, strips headings, bullets, quotes, emphasis and backticks, and skips text with no letters or digits (tested).
- `ReplyVoice.swift`: the voice to use: the saved voice if it's installed, else the best voice for the user's language: Personal Voice (only if already allowed; never asked for), then premium, enhanced, default; the user's own region wins a tie. Novelty voices are never picked.
- `SpeechSettings.swift`: preferences: `speaksReplies` (bool, default false) and `speechVoiceIdentifier` (optional `AVSpeechSynthesisVoice` identifier).

## Public surface
- `SpokenReply()`: `isOn`, `begin()`, `append(_ fragment:)`, `finish()`, `stop()`

## Gotchas
- A full stop is only a break when a space follows, so `3.5`, URLs and `wait...what` stay whole; a stop at the very end of the text waits for the next fragment or `finish()`.
- No break after `e.g.`, `i.e.`, `Mr.`, `Mrs.`, `Ms.`, `Dr.`, `Prof.`, `Sr.`, `Jr.`, `St.`, `vs.`, `approx.` or a bare number (so `1. Open Safari` stays one sentence).
- The voice is chosen at each reply's first sentence, so a voice installed in System Settings → Accessibility → Spoken Content is used from the next reply.
- Speech runs a little faster than the system default (1.1×). Set a voice with `defaults write com.macobar.app speechVoiceIdentifier <identifier>`.
- No audio session setup is needed on macOS, and no Info.plist keys or entitlements.

## Tested by
`MacobarTests/SpeechTests.swift`.

## Depends on
AVFoundation.
