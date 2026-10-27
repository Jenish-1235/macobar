# Providers
Which model providers macobar supports, how to reach each one, and where credentials are kept.

## Files
- `ProviderKind.swift`: the providers (Claude, Bedrock, OpenAI, ChatGPT, Gemini, Azure OpenAI, OpenRouter, OpenCode Zen) and what each needs: API format, sign-in method, extra setting, default model, key page. Also `APIFormat`, `SignInMethod`, `ProviderSetting`.
- `ProviderAccount.swift`: the user's choice: provider, model, and Azure resource or AWS region.
- `ProviderEndpoint.swift`: builds the request URL and auth headers for an account (tested).
- `KeychainStore.swift`: saves and reads secrets in the login Keychain.
- `ProviderAccountStore.swift`: the active account (preferences) and each provider's credential (Keychain).

## Public surface
- `ProviderKind.allCases`, `.apiFormat`, `.signInMethod`, `.requiredSetting`, `.defaultModel`, `.keyPageURL`
- `ProviderEndpoint(account:credential:)` → `url`, `headers`
- `ProviderAccountStore.activeAccount`, `activate(_:)`, `credential(for:)`, `saveCredential(_:for:)`

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

## Gotchas
- Secrets never go in preferences or logs; only the Keychain.
- Azure resource names and AWS regions are validated as a single host label, so a crafted value can't send the key to another host.
- Bedrock model IDs carry an `anthropic.` prefix (e.g. `anthropic.claude-opus-5-5`). Azure's "model" is the user's deployment name.
- ChatGPT plan usage only works on the Responses API, streaming, with `store: false`.

## Depends on
Nothing.
