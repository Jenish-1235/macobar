import Foundation
import Testing

/// Verifies each provider's address and authentication headers.
struct ProviderEndpointTests {
    /// Builds the endpoint for `kind` with a test credential.
    private func endpoint(_ kind: ProviderKind, setting: String? = nil) throws -> ProviderEndpoint {
        try ProviderEndpoint(account: ProviderAccount(kind: kind, model: "test-model", setting: setting), credential: "secret")
    }

    @Test("Claude uses the Messages API with an x-api-key header")
    func claude() throws {
        let endpoint = try endpoint(.claude)
        #expect(endpoint.url.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(endpoint.headers == ["x-api-key": "secret"])
    }

    @Test("Bedrock uses the regional Messages endpoint with an x-api-key header")
    func bedrock() throws {
        let endpoint = try endpoint(.bedrock, setting: " US-East-1 ")
        #expect(endpoint.url.absoluteString == "https://bedrock-mantle.us-east-1.api.aws/anthropic/v1/messages")
        #expect(endpoint.headers == ["x-api-key": "secret"])
    }

    @Test("OpenAI and ChatGPT use the Responses API with a bearer token")
    func openAIResponses() throws {
        for kind in [ProviderKind.openAI, .chatGPT] {
            let endpoint = try endpoint(kind)
            #expect(endpoint.url.absoluteString == "https://api.openai.com/v1/responses")
            #expect(endpoint.headers == ["Authorization": "Bearer secret"])
        }
    }

    @Test("Azure uses the resource's v1 endpoint with an api-key header")
    func azure() throws {
        let endpoint = try endpoint(.azureOpenAI, setting: "my-resource")
        #expect(endpoint.url.absoluteString == "https://my-resource.openai.azure.com/openai/v1/chat/completions")
        #expect(endpoint.headers == ["api-key": "secret"])
    }

    @Test("Chat Completions providers use their own base URLs", arguments: [
        (ProviderKind.gemini, "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"),
        (.openRouter, "https://openrouter.ai/api/v1/chat/completions"),
        (.openCodeZen, "https://opencode.ai/zen/v1/chat/completions"),
    ])
    func chatCompletions(kind: ProviderKind, address: String) throws {
        #expect(try endpoint(kind).url.absoluteString == address)
    }

    @Test("A missing resource or region is reported")
    func missingSetting() {
        #expect(throws: ProviderEndpointError.missingSetting(.azureResourceName)) { try endpoint(.azureOpenAI) }
        #expect(throws: ProviderEndpointError.missingSetting(.awsRegion)) { try endpoint(.bedrock, setting: "  ") }
    }

    @Test("A setting that would change the host is rejected")
    func hostInjection() {
        #expect(throws: ProviderEndpointError.invalidSetting(.azureResourceName)) {
            try endpoint(.azureOpenAI, setting: "evil.com/x?")
        }
    }

    @Test("Every cloud provider has an HTTPS endpoint")
    func everyCloudProviderUsesHTTPS() throws {
        for kind in ProviderKind.allCases where kind != .local {
            let setting = kind.requiredSetting == nil ? nil : "valid-label"
            #expect(try endpoint(kind, setting: setting).url.scheme == "https")
        }
    }

    @Test("A local server is reached at its address, with no credential sent", arguments: [
        "http://localhost:1234/v1",
        " http://localhost:1234/v1/ ",
    ])
    func localServer(address: String) throws {
        let endpoint = try endpoint(.local, setting: address)
        #expect(endpoint.url.absoluteString == "http://localhost:1234/v1/chat/completions")
        #expect(endpoint.headers.isEmpty)
    }

    @Test("A local server address must be a web address", arguments: ["localhost:1234", "ftp://localhost/v1", "not an address"])
    func invalidLocalAddress(address: String) {
        #expect(throws: ProviderEndpointError.invalidSetting(.serverAddress)) { try endpoint(.local, setting: address) }
    }
}
