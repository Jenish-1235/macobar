import Foundation

/// Cuts streamed reply text into sentences as soon as each one is complete.
struct SentenceSplitter {
    /// Characters that can end a sentence.
    private static let terminators: Set<Character> = [".", "!", "?"]
    /// Characters that may close a sentence after its terminator, as in `"Done."`, `**Done.**` or `__Done.__`.
    private static let closers: Set<Character> = ["\"", "'", "”", "’", ")", "]", "*", "_"]
    /// Characters that may open a word before an abbreviation, as in `(e.g.`.
    private static let openers: Set<Character> = ["\"", "'", "“", "‘", "(", "["]
    /// Lowercased words, without their last period, whose period doesn't end a sentence.
    private static let abbreviations: Set<String> = ["e.g", "i.e", "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "approx"]
    /// Opens and closes a Markdown code block, which is kept whole.
    private static let fence = "```"

    /// Text received but not yet part of a complete sentence.
    private var pending = ""

    /// Adds a streamed fragment and returns the sentences it completed, in order.
    mutating func append(_ fragment: String) -> [String] {
        pending += fragment
        var sentences: [String] = []
        while let end = nextSentenceEnd() {
            sentences.append(String(pending[..<end]))
            pending.removeSubrange(..<end)
        }
        return sentences.compactMap(Self.trimmed)
    }

    /// Returns whatever is left once the reply has ended, or nil if nothing is.
    mutating func finish() -> String? {
        defer { pending = "" }
        return Self.trimmed(pending)
    }

    /// Where the first complete sentence in `pending` ends, or nil until more text arrives.
    private func nextSentenceEnd() -> String.Index? {
        var index = pending.startIndex
        while index < pending.endIndex {
            let character = pending[index]
            if pending[index...].hasPrefix(Self.fence) {
                return index > pending.startIndex ? index : endOfCodeBlock()
            }
            if character.isNewline { return pending.index(after: index) }
            if Self.terminators.contains(character) {
                guard let runEnd = pending[index...].firstIndex(where: { !Self.terminators.contains($0) && !Self.closers.contains($0) }) else {
                    return nil
                }
                if pending[runEnd].isWhitespace, character != "." || !isAbbreviation(before: index) { return runEnd }
                index = runEnd
                continue
            }
            index = pending.index(after: index)
        }
        return nil
    }

    /// Where the code block opening `pending` closes, or nil while it's still open.
    private func endOfCodeBlock() -> String.Index? {
        let contentStart = pending.index(pending.startIndex, offsetBy: Self.fence.count)
        return pending[contentStart...].firstRange(of: Self.fence)?.upperBound
    }

    /// Whether the word ending at the period at `period` is an abbreviation or a number, so the period doesn't end a sentence.
    private func isAbbreviation(before period: String.Index) -> Bool {
        let wordStart = pending[..<period].lastIndex(where: \.isWhitespace).map { pending.index(after: $0) } ?? pending.startIndex
        let word = pending[wordStart..<period].drop { Self.openers.contains($0) }.lowercased()
        return Self.abbreviations.contains(word) || (!word.isEmpty && word.allSatisfy(\.isWholeNumber))
    }

    /// `text` without surrounding whitespace, or nil if nothing remains.
    private static func trimmed(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
