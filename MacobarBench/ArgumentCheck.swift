import Foundation

/// One condition a tool call's argument must meet.
enum ArgumentCheck: Sendable {
    /// The argument (key, text) contains the text, ignoring case; a list passes when any item does.
    case contains(String, String)
    /// The argument (key, text) is exactly the text, ignoring case.
    case equals(String, String)
    /// The argument (key, number) is the number.
    case number(String, Double)

    /// Whether `arguments` meet this check.
    func isMet(by arguments: [String: JSONValue]) -> Bool {
        switch self {
        case .contains(let key, let text):
            Self.texts(of: arguments[key]).contains { $0.localizedCaseInsensitiveContains(text) }
        case .equals(let key, let text):
            arguments[key]?.string?.caseInsensitiveCompare(text) == .orderedSame
        case .number(let key, let number):
            arguments[key]?.number == number
        }
    }

    /// How a failure names it, e.g. `minutes = 5`.
    var summary: String {
        switch self {
        case .contains(let key, let text): "\(key) containing \"\(text)\""
        case .equals(let key, let text): "\(key) = \(text)"
        case .number(let key, let number): "\(key) = \(String(format: "%g", number))"
        }
    }

    /// The text of a string argument, or of each string in a list argument.
    private static func texts(of value: JSONValue?) -> [String] {
        if let string = value?.string { return [string] }
        return value?.array?.compactMap(\.string) ?? []
    }
}
