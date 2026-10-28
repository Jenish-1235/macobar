import Foundation

/// One MCP server the user connected, minus its secrets (those live in `MCPServerSecrets`).
struct MCPServerConfig: Codable, Equatable, Sendable, Identifiable {
    /// How macobar reaches the server.
    enum Transport: Codable, Equatable, Sendable {
        /// A program on this Mac, spoken to over stdin and stdout; its secrets become environment variables.
        case command(executable: String, arguments: [String])
        /// A Streamable HTTP endpoint; its secrets become request headers.
        case address(url: URL)
    }

    /// Unique short name: lowercase letters, digits and hyphens, e.g. "github".
    let name: String
    /// How macobar reaches the server.
    let transport: Transport
    /// Whether its tools run without asking first.
    var isTrusted = false

    /// The name, which is unique.
    var id: String { name }

    /// Hosts plain http may reach: this Mac only, since anything else would carry the server's headers unencrypted.
    private static let loopbackHosts: Set = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// Whether `name` is non-empty, uses only lowercase letters, digits and single hyphens between them; so no two servers' tool names can turn out the same ("a-" + "_x" vs "a" + "__x").
    static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("-") && !name.hasSuffix("-") && !name.contains("--")
            && name.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    /// Whether `url` is an https address, or an http one on this Mac.
    static func isAllowedAddress(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased(), !host.isEmpty else { return false }
        switch url.scheme?.lowercased() {
        case "https": return true
        case "http": return loopbackHosts.contains(host)
        default: return false
        }
    }
}
