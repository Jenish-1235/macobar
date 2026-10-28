# ModelClient
Sends a conversation to the active provider and streams the reply back as text.

## Files
- `ChatMessage.swift`: one conversation turn (user or assistant, plain text).
- `ModelClient.swift`: builds the request, streams the response over HTTP, and turns each line into reply text.
- `WireFormat.swift`: the `WireFormat` protocol (request body, extra headers, reading a streamed line), `StreamEvent`, and `ProviderAccount.wireFormat`, which picks the format.
- `AnthropicMessagesFormat.swift`: Claude and Bedrock.
- `ChatCompletionsFormat.swift`: Gemini, Azure OpenAI, OpenRouter, OpenCode Zen.
- `ResponsesFormat.swift`: OpenAI and ChatGPT.
- `ModelClientError.swift`: why a reply failed (`rejected`, `failed`, `declined`), and reading the provider's error message from an HTTP error body.

## Public surface
- `ModelClient(account:credential:session:)`
- `streamReply(instructions:conversation:) -> AsyncThrowingStream<String, Error>`

## How a reply streams
1. `ProviderEndpoint` gives the URL and auth header; the wire format adds its own headers and the JSON body.
2. A non-2xx response throws `ModelClientError.rejected` with the provider's own message when the body has one.
3. Each `data:` line is read by the format: text deltas are yielded, `[DONE]` or the format's end event finishes, everything else is skipped.

## Gotchas
- Only `data:` lines are read, one JSON payload per line. `URLSession`'s `lines` drops blank lines, so events aren't grouped; none of the providers split a payload across lines.
- Claude: `thinking` is left out, so current models use their default (adaptive) and older ones still work. Thinking deltas are skipped. A `refusal` stop reason throws `declined`.
- Claude API server-side fallbacks (`fallbacks: "default"` + beta header) are sent only for the default model on the Claude API; Bedrock and other models may reject them.
- Responses requests are always `stream: true, store: false`, which ChatGPT sign-in requires.
- Gemini returns error bodies as a one-element array.

## Tested by
`MacobarTests/WireFormatTests.swift` (request bodies, recorded streams, error events) and `MacobarTests/ModelClientTests.swift` (HTTP round trips through a stub `URLProtocol`).

## Depends on
Providers.
