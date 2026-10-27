import Foundation
import Security

/// Stores secrets (API keys, sign-in tokens) in the user's login Keychain, never in plain files.
struct KeychainStore: Sendable {
    /// Keychain service name that groups all of macobar's secrets.
    private let service: String

    /// Creates a store for secrets under `service`.
    init(service: String = "com.macobar.app.credentials") {
        self.service = service
    }

    /// Saves `secret` under `name`, replacing any earlier value.
    func save(_ secret: String, as name: String) throws {
        let data = Data(secret.utf8)
        let status = SecItemUpdate(query(for: name) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return try check(status) }
        var item = query(for: name)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        try check(SecItemAdd(item as CFDictionary, nil))
    }

    /// The secret saved under `name`, or nil if there is none.
    func read(_ name: String) throws -> String? {
        var request = query(for: name)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        try check(status)
        return (result as? Data).map { String(decoding: $0, as: UTF8.self) }
    }

    /// The attributes that identify one of macobar's secrets.
    private func query(for name: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]
    }

    /// Turns a failed Keychain status into an error.
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}

/// A Keychain call that failed, with the system's explanation.
struct KeychainError: LocalizedError {
    /// The Security framework's result code.
    let status: OSStatus

    /// The system's description of the failure.
    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
    }
}
