import Foundation

/// Where to send an account's requests, and the headers that authenticate them.
struct ProviderEndpoint: Equatable, Sendable {
    /// Full URL of the provider's chat endpoint.
    let url: URL
    /// Authentication headers for every request.
    let headers: [String: String]

    /// Builds the endpoint for `account`, authenticated with `credential` (an API key or access token).
    init(account: ProviderAccount, credential: String) throws {
        guard let baseURL = URL(string: try Self.baseAddress(for: account)) else {
            throw ProviderEndpointError.invalidAddress
        }
        url = baseURL.appending(path: account.kind.apiFormat.path)
        headers = Self.authHeaders(for: account.kind, credential: credential)
    }

    /// The provider's base URL, with the account's resource or region filled in.
    private static func baseAddress(for account: ProviderAccount) throws -> String {
        switch account.kind {
        case .claude: return "https://api.anthropic.com/"
        case .bedrock: return try "https://bedrock-mantle.\(hostLabel(of: account)).api.aws/anthropic/"
        case .openAI, .chatGPT: return "https://api.openai.com/v1/"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai/"
        case .azureOpenAI: return try "https://\(hostLabel(of: account)).openai.azure.com/openai/v1/"
        case .openRouter: return "https://openrouter.ai/api/v1/"
        case .openCodeZen: return "https://opencode.ai/zen/v1/"
        }
    }

    /// The header each provider expects the credential in.
    private static func authHeaders(for kind: ProviderKind, credential: String) -> [String: String] {
        switch kind {
        case .claude, .bedrock: ["x-api-key": credential]
        case .azureOpenAI: ["api-key": credential]
        case .openAI, .chatGPT, .gemini, .openRouter, .openCodeZen: ["Authorization": "Bearer \(credential)"]
        }
    }

    /// The account's setting, checked to be a single host label so it can't redirect requests elsewhere.
    private static func hostLabel(of account: ProviderAccount) throws -> String {
        guard let setting = account.kind.requiredSetting else { throw ProviderEndpointError.invalidAddress }
        let label = (account.setting ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !label.isEmpty else { throw ProviderEndpointError.missingSetting(setting) }
        guard label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            throw ProviderEndpointError.invalidSetting(setting)
        }
        return label
    }
}

/// Why an account's endpoint couldn't be built.
enum ProviderEndpointError: LocalizedError, Equatable {
    /// The provider needs a setting the user hasn't entered.
    case missingSetting(ProviderSetting)
    /// The setting contains characters a host name can't have.
    case invalidSetting(ProviderSetting)
    /// The address couldn't be formed.
    case invalidAddress

    /// What to tell the user.
    var errorDescription: String? {
        switch self {
        case .missingSetting(let setting): "Enter your \(setting.label)."
        case .invalidSetting(let setting): "Your \(setting.label) can only contain letters, numbers and hyphens."
        case .invalidAddress: "macobar couldn't form this provider's address."
        }
    }
}
