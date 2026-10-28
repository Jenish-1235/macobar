import Foundation
import Network

/// Serves MCP over HTTP on 127.0.0.1, so AI apps on this Mac can use Macie's tools.
@MainActor
final class MCPServer {
    /// The fixed port, so the address apps are given never changes.
    private static let port: NWEndpoint.Port = 7766
    /// The URL apps connect to.
    static let address = "http://127.0.0.1:\(port.rawValue)\(MCPEndpoint.path)"

    /// Most connections served at once; enough for several apps each waiting on approvals in the Dock.
    private static let maxConnections = 32

    /// Queue the socket callbacks run on.
    private let queue = DispatchQueue(label: "com.macobar.mcp")
    /// Answers each request.
    private let endpoint: MCPEndpoint
    /// Turns connections away once `maxConnections` are open.
    private let connectionLimit = MCPConnectionLimit(maximum: maxConnections)
    /// The listening socket while the server runs.
    private var listener: NWListener?

    /// Creates a stopped server that answers with `endpoint`.
    init(endpoint: MCPEndpoint) {
        self.endpoint = endpoint
    }

    /// Starts listening on 127.0.0.1 only; `onFailure` hears why if the port can't be opened.
    func start(onFailure: @escaping @MainActor @Sendable (String) -> Void) throws {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: Self.port)
        parameters.acceptLocalOnly = true
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [endpoint, queue, connectionLimit] connection in
            guard connectionLimit.admit() else { return connection.cancel() }
            MCPConnection(connection: connection, endpoint: endpoint).start(on: queue, onEnd: connectionLimit.release)
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard case .failed(let error) = state else { return }
            Task { @MainActor in
                guard let self, let listener, self.listener === listener else { return }
                self.stop()
                onFailure(Self.explanation(of: error))
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    /// Stops accepting connections; requests already being answered finish.
    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// Why listening failed, in words for the user.
    private static func explanation(of error: NWError) -> String {
        if case .posix(.EADDRINUSE) = error { return "Port \(port.rawValue) is in use by another app. Quit it and turn sharing on again." }
        return "Couldn't start sharing: \(error.localizedDescription)"
    }
}
