/// Splits a typed command line into words the way a shell would, without running a shell.
enum CommandLineWords {
    /// The words of `line`: split on whitespace, with '…' and "…" quoting and \ escaping (outside single quotes).
    static func split(_ line: String) -> [String] {
        var words: [String] = []
        var word = ""
        var hasWord = false
        var quote: Character?
        var isEscaped = false
        for character in line {
            if isEscaped {
                word.append(character)
                isEscaped = false
            } else if character == "\\" && quote != "'" {
                isEscaped = true
                hasWord = true
            } else if let open = quote {
                if character == open { quote = nil } else { word.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
                hasWord = true
            } else if character.isWhitespace {
                if hasWord { words.append(word) }
                word = ""
                hasWord = false
            } else {
                word.append(character)
                hasWord = true
            }
        }
        if hasWord { words.append(word) }
        return words
    }
}
