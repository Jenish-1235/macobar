import Foundation

/// Any JSON value, for request bodies, streamed events, tool schemas and tool arguments.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Parses `text` as JSON.
    static func parse(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    /// Decodes whichever JSON type is present.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    /// Encodes the value as the matching JSON type.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// The value as compact JSON with sorted keys, so identical requests encode identically (and cache well).
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// The value as a compact JSON string.
    var jsonString: String {
        (try? encoded()).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }

    /// The member named `key`, when this is an object.
    subscript(key: String) -> JSONValue? {
        if case .object(let members) = self { members[key] } else { nil }
    }

    /// The text, when this is a string.
    var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    /// The number, when this is a number.
    var number: Double? {
        if case .number(let value) = self { value } else { nil }
    }

    /// The flag, when this is a boolean.
    var bool: Bool? {
        if case .bool(let value) = self { value } else { nil }
    }

    /// The elements, when this is an array.
    var array: [JSONValue]? {
        if case .array(let value) = self { value } else { nil }
    }

    /// The members, when this is an object.
    var object: [String: JSONValue]? {
        if case .object(let value) = self { value } else { nil }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    /// A string literal.
    init(stringLiteral value: String) { self = .string(value) }
    /// An integer literal.
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    /// A boolean literal.
    init(booleanLiteral value: Bool) { self = .bool(value) }
    /// An array literal.
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    /// A dictionary literal.
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { $1 }))
    }
    /// The `nil` literal, as JSON null.
    init(nilLiteral: ()) { self = .null }
}
