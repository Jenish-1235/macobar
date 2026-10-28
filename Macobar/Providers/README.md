# Providers
Which model providers macobar supports, how to reach each one, and where credentials are kept.

## Files
- `ProviderKind.swift`: the providers (Claude, Bedrock, OpenAI, ChatGPT, Gemini, Azure OpenAI, OpenRouter, OpenCode Zen, and a local model server "On this Mac") and what each needs: API format, sign-in method, extra setting, default model, key page. Also `APIFormat`, `SignInMethod`, `ProviderSetting` (with a suggested value for the local server address).
- `ProviderAccount.swift`: the user's choice: provider, model, and Azure resource, AWS region or local server address.
- `ProviderEndpoint.swift`: builds the request URL and auth headers for an account (tested).
- `KeychainStore.swift`: saves and reads secrets in the login Keychain.
- `ProviderAccountStore.swift`: the main (active) account and the optional fast account (preferences), and each provider's credential (Keychain; empty for a local server, which needs none).

## Public surface
- `ProviderKind.allCases`, `.apiFormat`, `.signInMethod`, `.requiredSetting`, `.defaultModel`, `.keyPageURL`
- `ProviderEndpoint(account:credential:)` → `url`, `headers`
- `ProviderAccountStore.activeAccount`, `activate(_:)`, `fastAccount`, `setFastAccount(_:)` (nil clears it), `credential(for:)`, `saveCredential(_:for:)`

## How each provider is reached
| Provider | Format | Base URL | Auth header |
|---|---|---|---|
| Claude | Anthropic Messages | `api.anthropic.com` | `x-api-key` |
| Bedrock | Anthropic Messages | `bedrock-mantle.{region}.api.aws/anthropic` | `x-api-key` (Bedrock API key) |
| OpenAI, ChatGPT | OpenAI Responses | `api.openai.com/v1` | `Authorization: Bearer` |
| Gemini | Chat Completions | `generativelanguage.googleapis.com/v1beta/openai` | `Authorization: Bearer` |
| Azure OpenAI | Chat Completions | `{resource}.openai.azure.com/openai/v1` | `api-key` |
| OpenRouter | Chat Completions | `openrouter.ai/api/v1` | `Authorization: Bearer` |
| OpenCode Zen | Chat Completions | `opencode.ai/zen/v1` | `Authorization: Bearer` |
| On this Mac (LM Studio, Ollama) | Chat Completions | the server address, e.g. `http://localhost:1234/v1` | none |

## Gotchas
- Secrets never go in preferences or logs; only the Keychain.
- Keys are saved per provider, so a main and a fast model on the same provider share one key.
- Azure resource names and AWS regions are validated as a single host label, so a crafted value can't send the key to another host.
- Bedrock model IDs carry an `anthropic.` prefix (e.g. `anthropic.claude-opus-5-5`). Azure's "model" is the user's deployment name.
- ChatGPT plan usage only works on the Responses API, streaming, with `store: false`.
- A local server address must be an http(s) URL; plain HTTP works because `NSAllowsLocalNetworking` is set in `project.yml`. Nothing secret is sent to it.

## Depends on
Nothing.
