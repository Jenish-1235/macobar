/// Builders for the JSON Schema snippets tools describe their arguments with.
enum Schema {
    /// An object with `properties`, of which `required` must be present.
    static func object(_ properties: [String: JSONValue] = [:], required: [String] = []) -> JSONValue {
        ["type": "object", "properties": .object(properties), "required": .array(required.map(JSONValue.string))]
    }

    /// A string argument.
    static func string(_ description: String) -> JSONValue {
        ["type": "string", "description": .string(description)]
    }

    /// A string argument limited to `values`.
    static func oneOf(_ values: [String], _ description: String) -> JSONValue {
        ["type": "string", "enum": .array(values.map(JSONValue.string)), "description": .string(description)]
    }

    /// A whole-number argument.
    static func integer(_ description: String) -> JSONValue {
        ["type": "integer", "description": .string(description)]
    }

    /// A numeric argument.
    static func number(_ description: String) -> JSONValue {
        ["type": "number", "description": .string(description)]
    }

    /// A true/false argument.
    static func boolean(_ description: String) -> JSONValue {
        ["type": "boolean", "description": .string(description)]
    }

    /// A list-of-strings argument.
    static func strings(_ description: String) -> JSONValue {
        ["type": "array", "items": ["type": "string"], "description": .string(description)]
    }
}
