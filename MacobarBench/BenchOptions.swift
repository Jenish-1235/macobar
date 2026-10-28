import Foundation

/// What the command line asked for: the model to measure and which scenarios to run.
struct BenchOptions: Sendable {
    /// How to call the bench, printed after a mistake.
    static let usage = """
        Usage: macobar-bench --provider local --model <id> [--address http://localhost:1234/v1] [--only <scenario>]
               macobar-bench --provider claude|openAI|gemini|openRouter|… --model <id> [--only <scenario>]
        Hosted providers read their API key from MACOBAR_API_KEY.
        """
    /// Environment variable holding the API key.
    private static let keyVariable = "MACOBAR_API_KEY"
    /// Options that take a value.
    private static let optionNames: Set = ["--provider", "--model", "--address", "--only"]

    /// The model under test.
    let account: ProviderAccount
    /// Its API key; empty for a provider that needs none.
    let credential: String
    /// The one scenario to run, or nil for all of them.
    let only: String?

    /// Reads `arguments` (without the program name), taking the API key from `environment`.
    init(arguments: [String], environment: [String: String]) throws {
        var values: [String: String] = [:]
        var remaining = arguments[...]
        while let option = remaining.popFirst() {
            guard Self.optionNames.contains(option) else { throw BenchUsageError("Unknown option \(option).") }
            guard let value = remaining.popFirst() else { throw BenchUsageError("\(option) needs a value.") }
            values[option] = value
        }
        guard let providerName = values["--provider"] else { throw BenchUsageError("Choose a provider with --provider.") }
        guard let kind = ProviderKind(rawValue: providerName) else {
            let names = ProviderKind.allCases.map(\.rawValue).joined(separator: ", ")
            throw BenchUsageError("Unknown provider \(providerName). Use one of: \(names).")
        }
        guard let model = values["--model"] ?? kind.defaultModel else { throw BenchUsageError("Choose a model with --model.") }
        let credential = kind.signInMethod == .none ? "" : environment[Self.keyVariable] ?? ""
        guard kind.signInMethod == .none || !credential.isEmpty else {
            throw BenchUsageError("Set \(Self.keyVariable) to your \(kind.displayName) API key.")
        }
        self.account = ProviderAccount(kind: kind, model: model, setting: values["--address"] ?? kind.requiredSetting?.suggestedValue)
        self.credential = credential
        self.only = values["--only"]
    }
}

/// A mistake on the command line, explained so it can be fixed.
struct BenchUsageError: LocalizedError {
    /// What went wrong and how to fix it.
    let message: String

    /// Creates an error with `message`.
    init(_ message: String) {
        self.message = message
    }

    /// The message, for `localizedDescription`.
    var errorDescription: String? { message }
}
