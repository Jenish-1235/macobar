import Foundation

/// The request format a provider speaks.
enum APIFormat: Sendable {
    /// Anthropic's Messages API.
    case anthropicMessages
    /// OpenAI's Chat Completions API, which most other providers also speak.
    case openAIChatCompletions
    /// OpenAI's Responses API, required for ChatGPT plan usage.
    case openAIResponses

    /// Endpoint path, relative to the provider's base URL.
    var path: String {
        switch self {
        case .anthropicMessages: "v1/messages"
        case .openAIChatCompletions: "chat/completions"
        case .openAIResponses: "responses"
        }
    }
}

/// How the user proves who they are to a provider.
enum SignInMethod: Sendable {
    /// A pasted API key.
    case apiKey
    /// Signing in with a ChatGPT account in the browser.
    case chatGPTAccount
    /// Nothing: a model server running on the user's own Mac.
    case none
}

/// An extra value a provider needs besides the credential.
enum ProviderSetting: Sendable {
    /// The Azure OpenAI resource name, the first part of its endpoint's host.
    case azureResourceName
    /// The AWS region Bedrock runs in.
    case awsRegion
    /// The address of a local model server, e.g. LM Studio's.
    case serverAddress

    /// Label shown next to the setting's field.
    var label: String {
        switch self {
        case .azureResourceName: "Azure resource name"
        case .awsRegion: "AWS region"
        case .serverAddress: "Server address"
        }
    }

    /// The value filled in before the user types one; nil where there's no sensible guess.
    var suggestedValue: String? {
        self == .serverAddress ? "http://localhost:1234/v1" : nil
    }
}

/// Every model provider macobar can talk to.
enum ProviderKind: String, CaseIterable, Codable, Sendable {
    case claude
    case bedrock
    case openAI
    case chatGPT
    case gemini
    case azureOpenAI
    case openRouter
    case openCodeZen
    case local

    /// Name shown in setup.
    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .bedrock: "Claude on Amazon Bedrock"
        case .openAI: "OpenAI"
        case .chatGPT: "ChatGPT"
        case .gemini: "Gemini"
        case .azureOpenAI: "Azure OpenAI"
        case .openRouter: "OpenRouter"
        case .openCodeZen: "OpenCode Zen"
        case .local: "On this Mac"
        }
    }

    /// The request format this provider speaks.
    var apiFormat: APIFormat {
        switch self {
        case .claude, .bedrock: .anthropicMessages
        case .openAI, .chatGPT: .openAIResponses
        case .gemini, .azureOpenAI, .openRouter, .openCodeZen, .local: .openAIChatCompletions
        }
    }

    /// How the user signs in.
    var signInMethod: SignInMethod {
        switch self {
        case .chatGPT: .chatGPTAccount
        case .local: .none
        default: .apiKey
        }
    }

    /// The extra value this provider needs, if any.
    var requiredSetting: ProviderSetting? {
        switch self {
        case .azureOpenAI: .azureResourceName
        case .bedrock: .awsRegion
        case .local: .serverAddress
        default: nil
        }
    }

    /// Model used until the user picks one; nil where models depend on the user's account.
    var defaultModel: String? {
        switch self {
        case .claude: "claude-opus-5-5"
        case .bedrock: "anthropic.claude-opus-5-5"
        default: nil
        }
    }

    /// Page where the user creates an API key; nil for providers that sign in or need no key.
    var keyPageURL: URL? {
        switch self {
        case .claude: URL(string: "https://platform.claude.com/settings/keys")
        case .bedrock: URL(string: "https://console.aws.amazon.com/bedrock/home#/api-keys")
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .chatGPT, .local: nil
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .azureOpenAI: URL(string: "https://portal.azure.com")
        case .openRouter: URL(string: "https://openrouter.ai/keys")
        case .openCodeZen: URL(string: "https://opencode.ai/auth")
        }
    }
}
