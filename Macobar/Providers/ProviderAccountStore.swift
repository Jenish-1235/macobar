import Foundation

/// Remembers the main and fast accounts (in preferences) and each provider's credential (in the Keychain).
struct ProviderAccountStore: Sendable {
    /// Preferences key holding the main account.
    private static let activeAccountKey = "activeProviderAccount"
    /// Preferences key holding the fast account.
    private static let fastAccountKey = "fastProviderAccount"
    /// Where the non-secret account details live; `UserDefaults` is thread-safe but not marked `Sendable`.
    nonisolated(unsafe) private let defaults: UserDefaults
    /// Where credentials live.
    private let keychain: KeychainStore

    /// Creates a store backed by `defaults` and `keychain`.
    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
    }

    /// The main model the user chose, or nil before they connect one.
    var activeAccount: ProviderAccount? {
        account(forKey: Self.activeAccountKey)
    }

    /// The model for quick requests, or nil when every request goes to the main one.
    var fastAccount: ProviderAccount? {
        account(forKey: Self.fastAccountKey)
    }

    /// Makes `account` the main model macobar talks to.
    func activate(_ account: ProviderAccount) throws {
        defaults.set(try JSONEncoder().encode(account), forKey: Self.activeAccountKey)
    }

    /// Makes `account` the fast model; nil stops using one.
    func setFastAccount(_ account: ProviderAccount?) throws {
        guard let account else { return defaults.removeObject(forKey: Self.fastAccountKey) }
        defaults.set(try JSONEncoder().encode(account), forKey: Self.fastAccountKey)
    }

    /// The saved API key or sign-in token for `kind`, or nil if there is none; empty for providers that need no key.
    func credential(for kind: ProviderKind) throws -> String? {
        guard kind.signInMethod != .none else { return "" }
        return try keychain.read(kind.rawValue)
    }

    /// Saves the API key or sign-in token for `kind`.
    func saveCredential(_ credential: String, for kind: ProviderKind) throws {
        try keychain.save(credential, as: kind.rawValue)
    }

    /// The account saved under `key`, or nil if there is none.
    private func account(forKey key: String) -> ProviderAccount? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ProviderAccount.self, from: $0) }
    }
}
