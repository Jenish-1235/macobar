import Foundation

/// Each server's secret environment variables or headers, one Keychain item per server.
struct MCPServerSecrets: Sendable {
    /// Where the secrets are kept.
    private let keychain: KeychainStore

    /// Creates secrets kept in `keychain`.
    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    /// The secrets saved for the server called `name`; none when nothing is saved.
    func values(forServerNamed name: String) throws -> [String: String] {
        guard let json = try keychain.read(Self.itemName(for: name)), !json.isEmpty else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: Data(json.utf8))
    }

    /// Saves `values` for the server called `name`, replacing earlier ones; empty clears them.
    func save(_ values: [String: String], forServerNamed name: String) throws {
        let json = String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
        try keychain.save(json, as: Self.itemName(for: name))
    }

    /// Reads "KEY=value" lines (blank lines skipped, the value may contain "="), or throws when a line isn't one.
    static func values(fromLines text: String) throws -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let entry = line.trimmingCharacters(in: .whitespaces)
            guard !entry.isEmpty else { continue }
            guard let separator = entry.firstIndex(of: "="), separator != entry.startIndex else {
                throw MCPSecretLineError()
            }
            let key = entry[..<separator].trimmingCharacters(in: .whitespaces)
            values[key] = entry[entry.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        }
        return values
    }

    /// The Keychain item holding the secrets of the server called `name`.
    private static func itemName(for name: String) -> String {
        "mcp-server.\(name)"
    }
}

/// A secret line that isn't "KEY=value"; the line isn't repeated, since it may hold a secret.
struct MCPSecretLineError: LocalizedError, Equatable {
    /// The message, for `localizedDescription`.
    var errorDescription: String? {
        "Write each secret as KEY=value on its own line, like GITHUB_TOKEN=ghp_…"
    }
}
