import Foundation
import Observation

/// State behind the Share Tools window: whether AI apps may use Macie's tools, and how to connect them.
@MainActor
@Observable
final class ToolSharingModel {
    /// Preferences key for the switch; sharing stays off until the user turns it on.
    private static let enabledKey = "sharesToolsWithAIApps"

    /// Whether AI apps may connect; saved, and applied at once.
    var isEnabled: Bool { didSet { applySwitch() } }
    /// The secret apps must send, or nil when the Keychain couldn't provide one.
    let token: String?
    /// Why sharing isn't working, if it failed.
    private(set) var failure: String?
    /// The server, or nil without a token.
    @ObservationIgnored private let server: MCPServer?

    /// Shares `tools`, asking `approver` before anything risky and reading or making the token in `keychain`; nothing listens until `startIfEnabled()`.
    init(tools: [any Tool], approver: @escaping MCPApprover, keychain: KeychainStore = KeychainStore()) {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        do {
            let token = try MCPAccessToken.load(from: keychain)
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            self.token = token
            server = MCPServer(endpoint: MCPEndpoint(token: token, handler: MCPRequestHandler(tools: tools, version: version, approver: approver)))
        } catch {
            token = nil
            server = nil
            failure = "Couldn't read the access token from your Keychain: \(error.localizedDescription)"
        }
    }

    /// Starts the server if the user left sharing on; call once at launch.
    func startIfEnabled() {
        if isEnabled { startServer() }
    }

    /// The Claude Code command that adds macobar with `token`.
    static func claudeCodeCommand(token: String) -> String {
        "claude mcp add --transport http macobar \(MCPServer.address) --header \"Authorization: Bearer \(token)\""
    }

    /// The `mcpServers` entry for Claude Desktop's config file: the bridge inside this app, with `token` in its environment.
    static func claudeDesktopConfig(token: String) -> String {
        let bridge = Bundle.main.bundleURL.appending(path: "Contents/MacOS/macobar-mcp").path(percentEncoded: false)
        let config: JSONValue = ["mcpServers": ["macobar": ["command": .string(bridge), "env": ["MACOBAR_TOKEN": .string(token)]]]]
        return config.jsonString
    }

    /// Saves the switch and starts or stops the server to match.
    private func applySwitch() {
        UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        if isEnabled {
            startServer()
        } else {
            server?.stop()
            failure = nil
        }
    }

    /// Starts listening, showing why if it can't.
    private func startServer() {
        guard let server else { return }
        failure = nil
        do {
            try server.start { [weak self] reason in self?.failure = reason }
        } catch {
            failure = "Couldn't start sharing: \(error.localizedDescription)"
        }
    }
}
