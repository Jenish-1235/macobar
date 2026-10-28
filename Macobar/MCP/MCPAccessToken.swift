import Foundation

/// The secret AI apps send to use Macie's tools: 32 random bytes as hex, made once and kept in the Keychain.
enum MCPAccessToken {
    /// Keychain name the token is saved under.
    private static let keychainName = "mcpToken"

    /// The saved token, making and saving one the first time.
    static func load(from keychain: KeychainStore) throws -> String {
        if let saved = try keychain.read(keychainName) { return saved }
        let token = generate()
        try keychain.save(token, as: keychainName)
        return token
    }

    /// A new token from the system's secure random generator.
    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }.joined()
    }
}
