# ModelClient
Sends a conversation (with tools) to the active provider and streams the reply back: text as it arrives, then the complete turn with any tool calls.

## Files
- `Conversation.swift`: `ConversationItem` (user text, assistant turn, tool results), `AssistantTurn`, `ToolCall`, `ToolResult` (with optional `images`), `ToolImage` (bytes, MIME type, `dataURL`), `ToolDefinition`.
- `JSONValue.swift`: any JSON value; bodies, events, schemas and arguments are built and read with it. Encodes with sorted keys so identical requests cache.
- `ModelClient.swift`: builds the request, streams the response over HTTP without following redirects, feeds each `data:` line to the format's reader, and yields `ModelEvent`s.
- `WireFormat.swift`: the `WireFormat` protocol (headers, request body, a `ReplyReader` per reply) and `ProviderAccount.wireFormat`, which picks the format.
- `AnthropicMessagesFormat.swift`: Claude and Bedrock, and the reader that rebuilds content blocks (text, thinking, tool use).
- `ChatCompletionsFormat.swift`: Gemini, Azure OpenAI, OpenRouter, OpenCode Zen, and the reader that joins tool-call fragments.
- `ResponsesFormat.swift`: OpenAI and ChatGPT, and the reader that collects output items.
- `ModelClientError.swift`: why a reply failed (`rejected`, `failed`, `declined`, `rateLimited` with the suggested wait), and reading the provider's error from HTTP bodies and stream events.

## Public surface
- `ModelClient(account:credential:session:)`
- `streamReply(instructions:conversation:tools:) -> AsyncThrowingStream<ModelEvent, Error>` (`.text`, then `.finished(AssistantTurn)`)

## How a reply streams
1. `ProviderEndpoint` gives the URL and auth header; the wire format adds its own headers and the JSON body.
2. Redirects are never followed (`RedirectRefuser`), so the credential in the headers only ever reaches the provider's own address; a 3xx is just another failed status.
3. A non-2xx response throws `ModelClientError.rejected` with the provider's own message when the body has one.
4. Each `data:` line goes to the format's `ReplyReader`: text is yielded as it comes; `[DONE]` or the format's end event stops reading; the reader then hands over the whole `AssistantTurn`.

## Gotchas
- Only `data:` lines are read, one JSON payload per line. `URLSession`'s `lines` drops blank lines, so events aren't grouped; none of the providers split a payload across lines.
- Claude: `thinking` is left out, so current models use their default (adaptive) and older ones still work. Thinking blocks are kept exactly as received (signature included) and replayed unchanged; editing or dropping them breaks tool loops. `refusal` throws `declined`; `max_tokens` throws so a half-written tool call never runs.
- Claude API only: server-side fallbacks (default model), automatic prompt caching (`cache_control` at the top level) and `eager_input_streaming` on tools. Bedrock gets none of these.
- Responses requests are always `stream: true, store: false` (ChatGPT sign-in requires it) and ask for `reasoning.encrypted_content`. Output items are replayed without their IDs, since unstored items can't be referenced, except reasoning items, which need theirs.
- Tool images: Claude gets them inside the `tool_result` (text, then base64 `image` blocks); Responses gets `function_call_output.output` as `input_text` + `input_image` parts; Chat Completions tool messages can't hold images, so one user message with `image_url` parts follows them. Results without images encode exactly as before. A model that can't take images fails that prompt only.
- Gemini attaches a thought signature to tool calls (`extra_content`); it's kept on `ToolCall.providerExtra` and sent back.
- Gemini returns error bodies as a one-element array.
- A hostile or broken stream can't crash the reader: a block or tool-call index too large for an `Int` is ignored (the default position is used instead of trapping), and so is a `retry-after` wait that is negative or not finite.

## Errors
- Stream error events show the provider's message and code; with neither, the raw event is shown so nothing is hidden.
- Only errors whose code mentions `rate_limit` become `rateLimited`; `insufficient_quota` and ChatGPT plan caps stay `rejected`.

## Tested by
`MacobarTests/WireFormatTests.swift` (request bodies with tool calls and results, recorded text and tool-call streams, error events) and `MacobarTests/ModelClientTests.swift` (HTTP round trips through a stub `URLProtocol`) `MacobarTests/RateLimitTests.swift`, `MacobarTests/ToolImageTests.swift` and `MacobarTests/DeviceSafetyTests.swift` (hostile stream indexes and retry-after values).

## Depends on
Providers, Tools (`RedirectRefuser`).
