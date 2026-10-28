# Voice
The Option-Space shortcut: tap it to type to Macie from anywhere, hold it to talk. What you say appears in the field as you speak and is sent when you let go. Speech is transcribed on this Mac; no audio leaves it.

## Files
- `VoiceController.swift`: registers the shortcut, tells taps from holds, runs listening, and reports everything as `VoiceEvent`s. Starts and stops never overlap: a new hold waits for the last one to finish. Turns the microphone off after 2 minutes of one hold.
- `HotkeyGesture.swift`: the pure tap-versus-hold rule (tested). Down then up within 0.35 s is a tap; still down at 0.35 s starts talking; up after that finishes. Key repeats are ignored.
- `GlobalHotkey.swift`: Option-Space registered with Carbon's `RegisterEventHotKey` on the event dispatcher target (so it fires even while a menu is open), reporting press and release on the main actor; unregistered on `stop()` or deinit.
- `SpeechInput.swift`: live transcription with `SpeechAnalyzer` and `SpeechTranscriber` (volatile results on). Asks for the microphone, picks the language, downloads its speech model when missing (reporting progress each second), converts the microphone's audio to the analyzer's best format, and streams the transcript; `stop()` finalizes and returns the final text.
- `Transcript.swift`: final text plus the latest volatile guess (tested).
- `VoiceEvent.swift`: what the chat bar hears: `focusField`, `status`, `listening`, `transcript`, `finished(prompt:)`, `failed`.
- `VoiceError.swift`: why the shortcut or listening failed, each with how to fix it.

## Public surface
- `VoiceController(onEvent:)`, `start()`, `stop()`
- `VoiceEvent`

## A hold, step by step
1. At 0.35 s: microphone access is checked (asked the first time), then the language: the user's own if on-device transcription supports it, otherwise US English.
2. If the language's speech model isn't on this Mac, it's downloaded once (`AssetInventory`), with `status` events like "Downloading speech recognition for English (United States): 40%".
3. The microphone turns on: `listening`, then a `transcript` each time the words change.
4. On release: input ends, the analyzer finalizes, then `transcript` with the final text and `finished(prompt:)` (nil when nothing was heard, so nothing is sent).
5. Letting go before the microphone is on ends with `finished(prompt: nil)`; a download already started keeps going, so the next hold is ready.
6. A hold lasts at most 2 minutes. After that the microphone turns off and nothing is sent, because the key's release was likely lost (Secure Keyboard Entry swallows Carbon hot keys).

## Permissions
- Microphone: `NSMicrophoneUsageDescription` and, with the hardened runtime, the `com.apple.security.device.audio-input` entitlement (both in `project.yml`). If the user said no, `failed` says to allow it in System Settings → Privacy & Security → Microphone.
- `SpeechAnalyzer` has no authorization call of its own (unlike `SFSpeechRecognizer`), so no speech recognition prompt appears.
- The shortcut needs no Accessibility access: Carbon hot keys are delivered to the app that registered them.

## Gotchas
- If another app already uses Option-Space, registration can fail; `start()` reports `failed` and taps and holds do nothing.
- The microphone tap is built in a nonisolated function: it runs on the audio thread, and a closure formed on the main actor would trap there under Swift 6.
- Final results are joined as the recognizer sends them (no added spaces), so languages without spaces stay correct.
- `installTap(onBus:bufferSize:format:block:)` is deprecated from macOS 27; it's used because macobar still supports macOS 26.

## Tested by
`MacobarTests/VoiceTests.swift`.

## Depends on
Nothing in macobar. System: Carbon (HIToolbox), AVFoundation, Speech.
