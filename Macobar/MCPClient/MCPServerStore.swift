import Foundation

/// The connected MCP servers, kept in a JSON file without their secrets.
struct MCPServerStore: Sendable {
    /// Where the servers live by default.
    static let defaultFileURL = URL.applicationSupportDirectory.appending(path: "macobar/mcp-servers.json")

    /// The JSON file holding the servers; read on every call, since it's the shared state.
    private let fileURL: URL

    /// Creates a store backed by `fileURL`.
    init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// Every server, in the order they were added.
    func servers() throws -> [MCPServerConfig] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([MCPServerConfig].self, from: Data(contentsOf: fileURL))
    }

    /// Adds `server`, refusing a malformed or taken name.
    func add(_ server: MCPServerConfig) throws {
        guard MCPServerConfig.isValidName(server.name) else { throw MCPServerStoreError.invalidName }
        var servers = try servers()
        guard !servers.contains(where: { $0.name == server.name }) else { throw MCPServerStoreError.duplicateName(server.name) }
        servers.append(server)
        try save(servers)
    }

    /// Removes the server called `name`; does nothing if there's none.
    func remove(named name: String) throws {
        try save(try servers().filter { $0.name != name })
    }

    /// Sets whether the server called `name` runs its tools without asking.
    func setTrusted(_ isTrusted: Bool, forServerNamed name: String) throws {
        var servers = try servers()
        guard let index = servers.firstIndex(where: { $0.name == name }) else { return }
        servers[index].isTrusted = isTrusted
        try save(servers)
    }

    /// Replaces the file with `servers` in one atomic write, creating its folder if needed.
    private func save(_ servers: [MCPServerConfig]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(servers).write(to: fileURL, options: .atomic)
    }
}

/// Why a server couldn't be added, in words the user can act on.
enum MCPServerStoreError: LocalizedError, Equatable {
    /// The name has characters other than lowercase letters, digits and hyphens, or a hyphen at an end or doubled.
    case invalidName
    /// Another server already has this name.
    case duplicateName(String)

    /// The message, for `localizedDescription`.
    var errorDescription: String? {
        switch self {
        case .invalidName: "Use only lowercase letters, digits and single hyphens between them for the name, like my-github."
        case .duplicateName(let name): "A server named \(name) already exists. Pick another name or remove that one first."
        }
    }
}
