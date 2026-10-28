import Foundation
import Network
import Synchronization

/// One client connection: reads a single HTTP request, sends the answer, then closes.
final class MCPConnection: Sendable {
    /// Most bytes read from the socket at a time.
    private static let readSize = 65_536
    /// Longest a client may take to send its whole request, so a stalled or trickling one can't hold its connection open.
    private static let readTimeout: DispatchTimeInterval = .seconds(10)

    /// The accepted socket.
    private let connection: NWConnection
    /// Decides the response to the request.
    private let endpoint: MCPEndpoint
    /// Whether the request has been read (or refused), after which the read timeout no longer applies.
    private let hasRequest = Mutex(false)

    /// Serves `connection` with `endpoint`.
    init(connection: NWConnection, endpoint: MCPEndpoint) {
        self.connection = connection
        self.endpoint = endpoint
    }

    /// Opens the connection on `queue` and starts reading, closing it if the request doesn't arrive in time; `onEnd` runs once it's closed.
    func start(on queue: DispatchQueue, onEnd: @escaping @Sendable () -> Void) {
        connection.stateUpdateHandler = { [connection] state in
            switch state {
            case .failed: connection.cancel()
            case .cancelled: onEnd()
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.readTimeout) { [self] in
            if !hasRequest.withLock({ $0 }) { connection.cancel() }
        }
        receive(after: Data())
    }

    /// Reads more bytes onto `buffer`, answering once it holds a whole request; closes if the client hangs up first.
    private func receive(after buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.readSize) { [self] content, _, isComplete, error in
            let buffer = buffer + (content ?? Data())
            do throws(HTTPRequestError) {
                if let request = try HTTPRequest.parse(buffer) {
                    hasRequest.withLock { $0 = true }
                    Task {
                        let response = await endpoint.response(to: request)
                        send(response)
                    }
                } else if isComplete || error != nil {
                    connection.cancel()
                } else {
                    receive(after: buffer)
                }
            } catch {
                hasRequest.withLock { $0 = true }
                send(MCPEndpoint.response(to: error))
            }
        }
    }

    /// Writes `response`, then closes the connection.
    private func send(_ response: HTTPResponse) {
        connection.send(content: response.serialized, completion: .contentProcessed { [connection] _ in connection.cancel() })
    }
}

/// Counts the connections being served and turns new ones away at a limit, so a flood of them can't exhaust memory.
final class MCPConnectionLimit: Sendable {
    /// Most connections served at once.
    private let maximum: Int
    /// Connections being served now.
    private let openCount = Mutex(0)

    /// Allows up to `maximum` connections at once.
    init(maximum: Int) {
        self.maximum = maximum
    }

    /// Takes a place for a new connection, or returns false when every place is taken.
    func admit() -> Bool {
        openCount.withLock { count in
            guard count < maximum else { return false }
            count += 1
            return true
        }
    }

    /// Gives back the place of a connection that closed.
    func release() {
        openCount.withLock { $0 = max($0 - 1, 0) }
    }
}
