import Foundation
import Observation

/// State behind the Connections window: the user's MCP servers, how each connected, and the form for adding one.
@MainActor
@Observable
final class ConnectionsModel {
    /// How a new server is reached.
    enum Kind: String, CaseIterable, Identifiable {
        /// A program on this Mac.
        case command = "Command"
        /// A server on the web.
        case address = "Address"

        /// The label, which is unique.
        var id: String { rawValue }
    }

    /// The connected servers, in the order they were added.
    private(set) var servers: [MCPServerConfig] = []
    /// How connecting to each server last went, by name.
    private(set) var statuses: [String: MCPServerStatus] = [:]
    /// Servers being tested right now.
    private(set) var testing: Set<String> = []
    /// Why the last change didn't work, if it didn't.
    private(set) var problem: String?
    /// The new server's name.
    var name = ""
    /// Whether the new server is a command or an address.
    var kind = Kind.command
    /// The new server's command line or URL.
    var target = ""
    /// The new server's secrets as "KEY=value" lines.
    var secretLines = ""

    /// Connects to the servers and runs their tools.
    @ObservationIgnored private let hub: MCPClientHub
    /// Where the servers are saved.
    @ObservationIgnored private let store: MCPServerStore
    /// Where their secrets are saved.
    @ObservationIgnored private let secrets: MCPServerSecrets

    /// Creates the model for the servers in `store`, connected through `hub`.
    init(hub: MCPClientHub, store: MCPServerStore = MCPServerStore(), secrets: MCPServerSecrets = MCPServerSecrets()) {
        self.hub = hub
        self.store = store
        self.secrets = secrets
    }

    /// Whether the form has a name and a command or address.
    var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !target.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Reloads the servers and how each last connected.
    func refresh() async {
        do {
            servers = try store.servers()
        } catch {
            problem = "Couldn't read your servers: \(error.localizedDescription)"
        }
        statuses = await hub.statuses
    }

    /// Saves the server in the form, clears the form, and tests the new server.
    func add() async {
        let name = self.name.trimmingCharacters(in: .whitespaces)
        do {
            let config = MCPServerConfig(name: name, transport: try transport())
            let values = try MCPServerSecrets.values(fromLines: secretLines)
            try store.add(config)
            do {
                try secrets.save(values, forServerNamed: name)
            } catch {
                try? store.remove(named: name)
                throw error
            }
            problem = nil
            self.name = ""
            target = ""
            secretLines = ""
            await refresh()
            await test(name)
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Removes the server called `name`, its secrets and its connection.
    func remove(_ name: String) async {
        do {
            try store.remove(named: name)
            try secrets.save([:], forServerNamed: name)
            ToolApprovals().revoke(namesStartingWith: RemoteToolName.make(server: name, tool: ""))
            problem = nil
        } catch {
            problem = "Couldn't remove \(name): \(error.localizedDescription)"
        }
        await hub.disconnect(serverNamed: name)
        await refresh()
    }

    /// Sets whether the server called `name` runs its tools without asking.
    func setTrusted(_ isTrusted: Bool, forServerNamed name: String) async {
        do {
            try store.setTrusted(isTrusted, forServerNamed: name)
            problem = nil
        } catch {
            problem = "Couldn't save the change: \(error.localizedDescription)"
        }
        await refresh()
    }

    /// Connects to the server called `name` afresh and shows its tool count or why it failed.
    func test(_ name: String) async {
        guard let config = servers.first(where: { $0.name == name }), !testing.contains(name) else { return }
        testing.insert(name)
        statuses[name] = await hub.test(config)
        testing.remove(name)
    }

    /// The form's command line or address as a transport.
    private func transport() throws -> MCPServerConfig.Transport {
        switch kind {
        case .command:
            let words = CommandLineWords.split(target)
            guard let executable = words.first else { throw ConnectionFormError.missingCommand }
            return .command(executable: executable, arguments: Array(words.dropFirst()))
        case .address:
            guard let url = URL(string: target.trimmingCharacters(in: .whitespaces)), MCPServerConfig.isAllowedAddress(url) else {
                throw ConnectionFormError.invalidAddress
            }
            return .address(url: url)
        }
    }
}

/// Why the form's command or address can't be used.
private enum ConnectionFormError: LocalizedError {
    /// The command line is blank.
    case missingCommand
    /// The address isn't an https URL, or an http one on this Mac.
    case invalidAddress

    /// The message, for `localizedDescription`.
    var errorDescription: String? {
        switch self {
        case .missingCommand: "Enter the command that starts the server, like npx -y @modelcontextprotocol/server-github."
        case .invalidAddress: "Enter the server's full address, starting with https:// (http:// only for a server on this Mac)."
        }
    }
}
