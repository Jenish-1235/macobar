import Foundation
import Observation

/// State behind the Connect screen: the role, the chosen provider, its key, model and setting, and the connection check.
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

    /// The job the connected model does.
    enum Role: CaseIterable {
        /// Answers everything, or only the harder requests when a fast model is set.
        case main
        /// Takes quick commands; anything harder goes to the main model.
        case fast

        /// Name shown on its choice.
        var title: String {
            switch self {
            case .main: "Main model"
            case .fast: "Fast model"
            }
        }
    }

    /// Providers offered; ChatGPT joins once sign-in exists.
    static let providers = ProviderKind.allCases.filter { $0.signInMethod != .chatGPTAccount }

    /// The job the model being set up will do; switching loads the account saved for it, or "On this Mac" for a new fast one.
    var role = Role.main { didSet { kind = savedAccount?.kind ?? .local } }
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
    /// The main model, or nil before one is connected; a fast model can be added only after it.
    private(set) var mainAccount: ProviderAccount?
    /// The fast model, or nil when every request goes to the main one.
    private(set) var fastAccount: ProviderAccount?
    /// Saved accounts and keys.
    @ObservationIgnored private let store: ProviderAccountStore
    /// Called once a provider is checked and saved.
    @ObservationIgnored private let onConnected: () -> Void

    /// Starts on the main model's account, or Claude when none is saved.
    init(store: ProviderAccountStore, onConnected: @escaping () -> Void) {
        self.store = store
        self.onConnected = onConnected
        let savedMain = store.activeAccount
        mainAccount = savedMain
        fastAccount = store.fastAccount
        kind = savedMain?.kind ?? .claude
        loadDetails()
    }

    /// Whether every required detail is filled in and no check is running.
    var canConnect: Bool {
        status != .checking
            && !model.trimmed.isEmpty
            && (hasSavedKey || !apiKey.trimmed.isEmpty)
            && (kind.requiredSetting == nil || !setting.trimmed.isEmpty)
    }

    /// The account saved for the chosen role, if any.
    private var savedAccount: ProviderAccount? {
        role == .main ? mainAccount : fastAccount
    }

    /// Checks the details with the provider, then saves the key and the account in its role.
    func connect() async {
        guard canConnect else { return }
        let account = ProviderAccount(kind: kind, model: model.trimmed, setting: kind.requiredSetting == nil ? nil : setting.trimmed)
        let newKey = apiKey.trimmed
        status = .checking
        do {
            let credential = newKey.isEmpty ? try store.credential(for: kind) ?? "" : newKey
            try await Self.checkConnection(ModelClient(account: account, credential: credential))
            if !newKey.isEmpty { try store.saveCredential(newKey, for: kind) }
            try save(account)
            status = .editing
            onConnected()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Stops using a fast model, so every request goes to the main one.
    func removeFastModel() {
        do {
            try store.setFastAccount(nil)
            fastAccount = nil
            if role == .fast { role = .main }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Saves `account` as the main or fast model, whichever role is chosen.
    private func save(_ account: ProviderAccount) throws {
        switch role {
        case .main:
            try store.activate(account)
            mainAccount = account
        case .fast:
            try store.setFastAccount(account)
            fastAccount = account
        }
    }

    /// Asks for a tiny reply; any text back proves the key, model and address work.
    private static func checkConnection(_ client: ModelClient) async throws {
        let ping: [ConversationItem] = [.user("Reply with the single word: ready")]
        for try await _ in client.streamReply(instructions: "Reply with one word.", conversation: ping) { return }
    }

    /// Fills the fields for `kind`: the role's saved account details if it's that provider, otherwise defaults.
    private func loadDetails() {
        let saved = savedAccount.flatMap { $0.kind == kind ? $0 : nil }
        model = saved?.model ?? kind.defaultModel ?? ""
        setting = saved?.setting ?? kind.requiredSetting?.suggestedValue ?? ""
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
