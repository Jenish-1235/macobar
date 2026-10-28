import Foundation

/// Remembers which provider is active (in preferences) and each provider's credential (in the Keychain).
struct ProviderAccountStore: Sendable {
    /// Preferences key holding the active account.
    private static let activeAccountKey = "activeProviderAccount"
    /// Where the non-secret account details live; `UserDefaults` is thread-safe but not marked `Sendable`.
    nonisolated(unsafe) private let defaults: UserDefaults
    /// Where credentials live.
    private let keychain: KeychainStore

    /// Creates a store backed by `defaults` and `keychain`.
    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
    }

    /// The provider the user chose, or nil before they connect one.
    var activeAccount: ProviderAccount? {
        defaults.data(forKey: Self.activeAccountKey).flatMap { try? JSONDecoder().decode(ProviderAccount.self, from: $0) }
    }

    /// Makes `account` the one macobar talks to.
    func activate(_ account: ProviderAccount) throws {
        defaults.set(try JSONEncoder().encode(account), forKey: Self.activeAccountKey)
    }

    /// The saved API key or sign-in token for `kind`, or nil if there is none.
    func credential(for kind: ProviderKind) throws -> String? {
        try keychain.read(kind.rawValue)
    }

    /// Saves the API key or sign-in token for `kind`.
    func saveCredential(_ credential: String, for kind: ProviderKind) throws {
        try keychain.save(credential, as: kind.rawValue)
    }
}
