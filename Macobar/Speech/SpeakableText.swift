import Foundation

/// Turns reply text into what should be read aloud: no code blocks, links said as "link", no Markdown symbols.
enum SpeakableText {
    /// The words in `text` worth saying, or an empty string when nothing is (a code block, a rule, only symbols).
    static func from(_ text: String) -> String {
        let spoken = text
            .replacing(#/```[\s\S]*?(?:```|$)/#, with: "")
            .replacing(#/!?\[([^\]]*)\]\([^)]*\)/#) { $0.output.1 }
            .replacing(#/(?:https?://|www\.)\S*[^\s.,!?;:)\]"']/#, with: "link")
            .replacing(#/^[ \t]*(?:#{1,6}|>|[-*+])[ \t]+/#.anchorsMatchLineEndings(), with: "")
            .replacing(#/\*\*|__|~~|[*`]/#, with: "")
            .replacing(#/\s+/#, with: " ")
            .trimmingCharacters(in: .whitespaces)
        return spoken.contains { $0.isLetter || $0.isNumber } ? spoken : ""
    }
}
