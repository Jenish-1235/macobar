/// A tool call's arguments, with typed accessors.
struct ToolInput: Sendable {
    /// The decoded JSON arguments.
    let arguments: [String: JSONValue]

    /// Wraps decoded arguments.
    init(_ arguments: [String: JSONValue] = [:]) {
        self.arguments = arguments
    }

    /// The string at `key`, or nil when missing or blank.
    func string(_ key: String) -> String? {
        guard let value = arguments[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    /// The string at `key`, or an error the model can fix.
    func requiredString(_ key: String) throws -> String {
        guard let value = string(key) else { throw ToolError("Missing required argument \"\(key)\".") }
        return value
    }

    /// The string at `key` exactly as given, keeping surrounding whitespace (for text to type or write).
    func rawString(_ key: String) -> String? {
        arguments[key]?.string
    }

    /// The whole number at `key`, or nil when missing or too large to be one.
    func integer(_ key: String) -> Int? {
        arguments[key]?.number.flatMap { Int(exactly: $0.rounded(.towardZero)) }
    }

    /// The number at `key`, if any.
    func number(_ key: String) -> Double? {
        arguments[key]?.number
    }

    /// The flag at `key`, or `fallback` when missing.
    func bool(_ key: String, default fallback: Bool = false) -> Bool {
        arguments[key]?.bool ?? fallback
    }

    /// The strings in the array at `key`, or an empty list.
    func strings(_ key: String) -> [String] {
        arguments[key]?.array?.compactMap(\.string) ?? []
    }
}
