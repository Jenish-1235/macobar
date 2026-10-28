import Foundation
import Synchronization

/// How connecting to one server last went, for the Connections window.
enum MCPServerStatus: Equatable, Sendable {
    /// Connected, offering this many tools.
    case connected(toolCount: Int)
    /// Couldn't connect, for this reason.
    case failed(String)
}

/// Connects to the user's MCP servers when their tools are first needed, keeps each tool list, and runs the tools.
actor MCPClientHub {
    /// How long a server that failed to connect is left before it's tried again; Test or new settings retry at once.
    private static let retryPause = Duration.seconds(300)

    /// What a connection was opened with; when it changes, the server is connected afresh.
    private struct ConnectionSettings: Equatable, Sendable {
        /// The command or address.
        let transport: MCPServerConfig.Transport
        /// The environment variables or headers.
        let secrets: [String: String]
    }

    /// A live connection and the tools the server listed on it.
    private struct ConnectedServer: Sendable {
        /// Carries the messages; closed to disconnect.
        let transport: any MCPTransport
        /// The MCP session.
        let client: MCPClient
        /// The server's tools, listed once per connection.
        let tools: [MCPToolInfo]
    }

    /// A connection being made or made, and what it was opened with.
    private struct Session {
        /// What the connection was opened with.
        let settings: ConnectionSettings
        /// The handshake and tool listing, shared by everyone waiting on it.
        let connection: Task<ConnectedServer, Error>
        /// When the connection was started, so one that failed isn't retried on every prompt.
        let startedAt = ContinuousClock.now
    }

    /// The servers the user connected.
    private let store: MCPServerStore
    /// Their environment variables and headers.
    private let secrets: MCPServerSecrets
    /// Each server's connection, by name.
    private var sessions: [String: Session] = [:]
    /// How connecting to each server last went, by name.
    private(set) var statuses: [String: MCPServerStatus] = [:]
    /// Every transport not yet closed, so `stop()` can close them without waiting for the actor.
    private let openTransports = Mutex<[any MCPTransport]>([])

    /// Creates a hub for the servers in `store`, with secrets from `secrets`; nothing connects until tools are asked for.
    init(store: MCPServerStore = MCPServerStore(), secrets: MCPServerSecrets = MCPServerSecrets()) {
        self.store = store
        self.secrets = secrets
    }

    /// Every connected server's tools, one per name (the server added first winning, never whichever answered first), connecting the servers at once where needed; servers that fail are skipped and their failure recorded.
    func tools() async -> [any Tool] {
        let configs = (try? store.servers()) ?? []
        let names = Set(configs.map(\.name))
        for name in sessions.keys where !names.contains(name) { disconnect(serverNamed: name) }
        let toolLists = await withTaskGroup(of: (index: Int, tools: [any Tool]).self) { group in
            for (index, config) in configs.enumerated() {
                group.addTask { (index, await self.tools(of: config)) }
            }
            var lists = Array(repeating: [any Tool](), count: configs.count)
            for await serverTools in group { lists[serverTools.index] = serverTools.tools }
            return lists
        }
        var seenNames = Set<String>()
        return toolLists.joined().filter { seenNames.insert($0.name).inserted }
    }

    /// Connects to `config`'s server afresh and says how it went.
    func test(_ config: MCPServerConfig) async -> MCPServerStatus {
        disconnect(serverNamed: config.name)
        do {
            return .connected(toolCount: try await connectedServer(for: config).tools.count)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Runs `tool` on the server called `server` with `arguments`, reconnecting first if its connection ended.
    func callTool(named tool: String, onServerNamed server: String, arguments: [String: JSONValue]) async throws -> (text: String, images: [ToolImage]) {
        guard let config = try store.servers().first(where: { $0.name == server }) else {
            throw ToolError("The \(server) server was removed from Connections. Don't use its tools.")
        }
        return try await connectedServer(for: config).client.callTool(named: tool, arguments: arguments)
    }

    /// Ends the connection to the server called `name`, stopping its process, and forgets its status.
    func disconnect(serverNamed name: String) {
        statuses[name] = nil
        guard let connection = sessions.removeValue(forKey: name)?.connection else { return }
        connection.cancel()
        Task {
            if let server = try? await connection.value { close(server.transport) }
        }
    }

    /// Closes every connection and stops every server process at once; call on quit.
    nonisolated func stop() {
        openTransports.withLock { transports in
            transports.forEach { $0.close() }
            transports = []
        }
    }

    /// `config`'s tools as Macie's own, or none when its server can't connect.
    private func tools(of config: MCPServerConfig) async -> [any Tool] {
        guard let server = try? await connectedServer(for: config) else { return [] }
        return server.tools.map { RemoteTool(info: $0, serverName: config.name, isTrusted: config.isTrusted, hub: self) }
    }

    /// The live connection to `config`'s server: the current one if its settings match and it's still open (or its recent failure), otherwise a new one.
    private func connectedServer(for config: MCPServerConfig) async throws -> ConnectedServer {
        let settings: ConnectionSettings
        do {
            settings = ConnectionSettings(transport: config.transport, secrets: try secrets.values(forServerNamed: config.name))
        } catch {
            statuses[config.name] = .failed("Couldn't read this server's secrets from your Keychain: \(error.localizedDescription)")
            throw error
        }
        if let session = sessions[config.name], session.settings == settings {
            let outcome = await session.connection.result
            guard sessions[config.name]?.connection == session.connection else { return try await connectedServer(for: config) }
            switch outcome {
            case .success(let server) where server.transport.isOpen: return server
            case .failure(let error) where ContinuousClock.now < session.startedAt + Self.retryPause: throw error
            default: break
            }
        }
        disconnect(serverNamed: config.name)
        let connection = Task { try await connect(with: settings) }
        sessions[config.name] = Session(settings: settings, connection: connection)
        do {
            let server = try await connection.value
            statuses[config.name] = .connected(toolCount: server.tools.count)
            return server
        } catch {
            statuses[config.name] = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Starts the server's transport, does the handshake and lists its tools; closes the transport if any step fails.
    private nonisolated func connect(with settings: ConnectionSettings) async throws -> ConnectedServer {
        let transport: any MCPTransport = switch settings.transport {
        case .command(let executable, let arguments):
            try await StdioTransport.start(executable: executable, arguments: arguments, environment: settings.secrets)
        case .address(let url):
            StreamableHTTPTransport(url: url, headers: settings.secrets)
        }
        openTransports.withLock { $0.append(transport) }
        do {
            let client = try await MCPClient.connect(over: transport)
            return ConnectedServer(transport: transport, client: client, tools: try await client.listTools())
        } catch {
            close(transport)
            throw error
        }
    }

    /// Closes `transport` and stops tracking it.
    private nonisolated func close(_ transport: any MCPTransport) {
        transport.close()
        openTransports.withLock { $0.removeAll { $0 === transport } }
    }
}
