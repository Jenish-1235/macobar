import Foundation
import Observation

/// State behind the Connect screen: the chosen provider, its key, model and setting, and the connection check.
@MainActor
@Observable
final class ConnectModel {
    /// Where the connection attempt stands.
    enum Status: Equatable {
        /// Waiting for the user.
        case editing
        /// Asking the provider for a short reply.
        case checking
        /// The check failed, with the reason to show.
        case failed(String)
    }

    /// Providers offered; ChatGPT joins once sign-in exists.
    static let providers = ProviderKind.allCases.filter { $0.signInMethod == .apiKey }

    /// The provider being set up.
    var kind: ProviderKind { didSet { loadDetails() } }
    /// A newly pasted key; empty keeps the saved one.
    var apiKey = "" { didSet { clearFailure() } }
    /// Model ID, or the Azure deployment name.
    var model = "" { didSet { clearFailure() } }
    /// AWS region or Azure resource name.
    var setting = "" { didSet { clearFailure() } }
    /// Where the connection attempt stands.
    private(set) var status = Status.editing
    /// Whether the Keychain already holds a key for `kind`.
    private(set) var hasSavedKey = false
    /// Saved accounts and keys.
    @ObservationIgnored private let store: ProviderAccountStore
    /// Called once a provider is checked and saved.
    @ObservationIgnored private let onConnected: () -> Void

    /// Starts from the active account, or Claude when none is saved.
    init(store: ProviderAccountStore, onConnected: @escaping () -> Void) {
        self.store = store
        self.onConnected = onConnected
        kind = store.activeAccount?.kind ?? .claude
        loadDetails()
    }

    /// Whether every required detail is filled in and no check is running.
    var canConnect: Bool {
        status != .checking
            && !model.trimmed.isEmpty
            && (hasSavedKey || !apiKey.trimmed.isEmpty)
            && (kind.requiredSetting == nil || !setting.trimmed.isEmpty)
    }

    /// Checks the details with the provider, then saves the key and makes this provider active.
    func connect() async {
        guard canConnect else { return }
        let account = ProviderAccount(kind: kind, model: model.trimmed, setting: kind.requiredSetting == nil ? nil : setting.trimmed)
        let newKey = apiKey.trimmed
        status = .checking
        do {
            let credential = newKey.isEmpty ? try store.credential(for: kind) ?? "" : newKey
            try await Self.checkConnection(ModelClient(account: account, credential: credential))
            if !newKey.isEmpty { try store.saveCredential(newKey, for: kind) }
            try store.activate(account)
            status = .editing
            onConnected()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Asks for a tiny reply; any text back proves the key, model and address work.
    private static func checkConnection(_ client: ModelClient) async throws {
        let ping = [ChatMessage(role: .user, text: "Reply with the single word: ready")]
        for try await _ in client.streamReply(instructions: "Reply with one word.", conversation: ping) { return }
    }

    /// Fills the fields for `kind`: the saved account's details if it's the active one, otherwise defaults.
    private func loadDetails() {
        let saved = store.activeAccount.flatMap { $0.kind == kind ? $0 : nil }
        model = saved?.model ?? kind.defaultModel ?? ""
        setting = saved?.setting ?? ""
        apiKey = ""
        hasSavedKey = ((try? store.credential(for: kind)) ?? nil) != nil
        status = .editing
    }

    /// Drops a stale failure message once the user edits a field.
    private func clearFailure() {
        if case .failed = status { status = .editing }
    }
}

private extension String {
    /// The string without surrounding spaces and newlines.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
