import Foundation

/// Splits a document's text into overlapping passages small enough to embed.
enum TextChunker {
    /// Longest passage, in characters.
    static let chunkLength = 1_200
    /// Characters each passage repeats from the end of the one before, so no sentence is cut off from its context.
    static let overlap = 200

    /// The passages of `text`, with whitespace runs collapsed to single spaces and cuts made between words where possible.
    static func chunks(of text: String) -> [String] {
        let characters = Array(text.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        var chunks: [String] = []
        var start = 0
        while start < characters.count {
            var end = min(start + chunkLength, characters.count)
            if end < characters.count, let space = characters[(end - overlap)..<end].lastIndex(of: " ") {
                end = space
            }
            chunks.append(String(characters[start..<end]).trimmingCharacters(in: .whitespaces))
            guard end < characters.count else { break }
            let overlapStart = max(end - overlap, start + 1)
            start = characters[overlapStart..<end].firstIndex(of: " ").map { $0 + 1 } ?? overlapStart
        }
        return chunks.filter { !$0.isEmpty }
    }
}
