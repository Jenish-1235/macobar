import Foundation
import Synchronization

/// Talks to an MCP server run as a program on this Mac: one JSON-RPC message per line on stdin and stdout.
final class StdioTransport: MCPTransport {
    /// Longest wait for a reply, in seconds.
    private static let timeout = 30.0
    /// Used when the login shell can't report its PATH.
    private static let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    /// The user's login PATH, so names like npx and uvx resolve as in Terminal; resolved once, on first use.
    private static let loginPath = Task { await resolveLoginPath() }
    /// The only variables passed on from macobar's own environment, as the MCP SDKs do; anything else (API keys from a Terminal launch, SSH_AUTH_SOCK) reaches a server only through its own secrets.
    private static let inheritedVariables: Set = ["HOME", "LOGNAME", "USER", "SHELL", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "__CF_USER_TEXT_ENCODING"]

    /// Requests waiting for replies, and why the connection ended once it has.
    private struct State {
        /// Each waiting request's continuation, by id.
        var waiting: [Int: CheckedContinuation<JSONValue, Error>] = [:]
        /// Why the connection ended, or nil while it's open.
        var endReason: MCPClientError?
    }

    /// The server's process.
    private let process: Process
    /// The server's stdin; locked so concurrent messages never interleave.
    private let input: Mutex<FileHandle>
    /// Waiting requests and whether the connection ended.
    private let state = Mutex(State())

    /// Wraps a started `process` writing to `input`.
    private init(process: Process, input: FileHandle) {
        self.process = process
        self.input = Mutex(input)
    }

    /// Starts `executable` with `arguments` through /usr/bin/env, with the basics of macobar's environment, the login PATH and the server's `environment`.
    static func start(executable: String, arguments: [String], environment: [String: String]) async throws -> StdioTransport {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.environment = childEnvironment(inheriting: ProcessInfo.processInfo.environment, path: await loginPath.value, secrets: environment)
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let transport = StdioTransport(process: process, input: stdin.fileHandleForWriting)
        process.terminationHandler = { [weak transport] process in
            transport?.end(because: .exited(command: executable, status: process.terminationStatus))
        }
        try process.run()
        transport.readReplies(from: stdout.fileHandleForReading)
        return transport
    }

    /// Whether the process is still running and hasn't been closed.
    var isOpen: Bool {
        state.withLock { $0.endReason == nil }
    }

    /// Writes `message` as one line and waits up to 30 seconds for the reply to `id`.
    func request(_ message: JSONValue, id: Int) async throws -> JSONValue {
        let line = try message.encoded() + Data("\n".utf8)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let endReason = state.withLock { state -> MCPClientError? in
                    if state.endReason == nil { state.waiting[id] = continuation }
                    return state.endReason
                }
                if let endReason { return continuation.resume(throwing: endReason) }
                if Task.isCancelled { return fail(id, with: CancellationError()) }
                do {
                    try write(line)
                } catch {
                    return fail(id, with: MCPClientError.closed)
                }
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.timeout))
                    self?.fail(id, with: MCPClientError.timedOut)
                }
            }
        } onCancel: {
            fail(id, with: CancellationError())
        }
    }

    /// Writes `message` as one line.
    func notify(_ message: JSONValue) async throws {
        do {
            try write(try message.encoded() + Data("\n".utf8))
        } catch {
            throw MCPClientError.closed
        }
    }

    /// Fails waiting requests, stops the process and closes stdin (after stopping, so a stuck write can't block it).
    func close() {
        end(because: .closed)
        if process.isRunning { process.terminate() }
        try? input.withLock { try $0.close() }
    }

    /// Writes `data` to stdin in one piece.
    private func write(_ data: Data) throws {
        try input.withLock { try $0.write(contentsOf: data) }
    }

    /// Reads stdout line by line, handing each reply to its waiting request, until the process closes it.
    private func readReplies(from output: FileHandle) {
        Task.detached { [self] in
            do {
                for try await line in NewlineSeparatedLines(bytes: output.bytes) {
                    guard let message = try? JSONRPC.value(fromJSON: Data(line.utf8)), let id = message["id"]?.number.flatMap({ Int(exactly: $0) }),
                        JSONRPC.isReply(message, to: id) else { continue }
                    resume(id, with: message)
                }
            } catch MCPClientError.tooLarge {
                end(because: .tooLarge)
                process.terminate()
            } catch {
                // A failed read means the pipe closed; the termination handler reports why.
            }
        }
    }

    /// Hands `reply` to the request waiting for `id`, if any.
    private func resume(_ id: Int, with reply: JSONValue) {
        state.withLock { $0.waiting.removeValue(forKey: id) }?.resume(returning: reply)
    }

    /// Fails the request waiting for `id`, if it still is.
    private func fail(_ id: Int, with error: Error) {
        state.withLock { $0.waiting.removeValue(forKey: id) }?.resume(throwing: error)
    }

    /// Marks the connection ended (keeping an earlier reason, such as `close()`) and fails every waiting request.
    private func end(because reason: MCPClientError) {
        let (waiting, finalReason) = state.withLock { state in
            let finalReason = state.endReason ?? reason
            let waiting = Array(state.waiting.values)
            state = State(endReason: finalReason)
            return (waiting, finalReason)
        }
        waiting.forEach { $0.resume(throwing: finalReason) }
    }

    /// The environment a server runs with: only `inheritedVariables` from `inherited`, then `path` as PATH, then the server's `secrets` over both.
    static func childEnvironment(inheriting inherited: [String: String], path: String, secrets: [String: String]) -> [String: String] {
        inherited.filter { inheritedVariables.contains($0.key) }
            .merging(["PATH": path]) { $1 }
            .merging(secrets) { $1 }
    }

    /// The PATH a login zsh reports, or a common default when it can't be read.
    private static func resolveLoginPath() async -> String {
        let output = try? await ProcessRunner.run("/bin/zsh", ["-lc", "echo $PATH"], timeout: 10)
        let path = output?.split(separator: "\n").last.map(String.init) ?? ""
        return path.contains("/") ? path : fallbackPath
    }
}
