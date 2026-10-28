/// Turns a server's name and one of its tool names into a name every model provider accepts.
enum RemoteToolName {
    /// Longest tool name providers accept.
    static let maximumLength = 64
    /// Characters kept before the hash when a name is too long, leaving room for "_" and 8 hex digits.
    private static let keptLength = maximumLength - 9

    /// "<server>__<tool>" in lowercase with anything but a-z, 0-9 and _ turned into _; a name too long is cut and given a hash of the whole, so it stays unique and the same on every launch.
    static func make(server: String, tool: String) -> String {
        let name = String(String.UnicodeScalarView("\(server)__\(tool)".lowercased().unicodeScalars.map { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) ? scalar : "_"
        }))
        guard name.count > maximumLength else { return name }
        return name.prefix(keptLength) + "_" + hexHash(of: name)
    }

    /// A server's tool name as shown to the user: ASCII letters, digits, "_", "-" and "." kept, anything else (spaces, line breaks, look-alike or right-to-left characters) turned into "_", cut to `maximumLength`.
    static func shown(_ tool: String) -> String {
        String(String.UnicodeScalarView(tool.unicodeScalars.prefix(maximumLength).map { scalar in
            scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || "_-.".unicodeScalars.contains(scalar)) ? scalar : "_"
        }))
    }

    /// The 32-bit FNV-1a hash of `text` as 8 hex digits; unlike `Hasher`, it's the same on every launch.
    private static func hexHash(of text: String) -> String {
        let hash = text.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 8 - hex.count) + hex
    }
}
