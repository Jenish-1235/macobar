/// A byte stream's lines split only at "\n", blank ones kept; unlike `lines`, U+2028 and U+2029 (raw in some JSON) don't split.
struct NewlineSeparatedLines<Bytes: AsyncSequence>: AsyncSequence where Bytes.Element == UInt8 {
    /// The bytes being split.
    let bytes: Bytes
    /// Longest line read, in bytes; a longer one throws `MCPClientError.tooLarge` instead of growing without end.
    var maximumLength = JSONRPC.maximumMessageBytes

    /// Reads the bytes one line at a time.
    struct AsyncIterator: AsyncIteratorProtocol {
        /// Where the bytes come from.
        var byteIterator: Bytes.AsyncIterator
        /// Longest line read, in bytes.
        let maximumLength: Int

        /// The next line, or nil once the bytes run out; a last line without "\n" still counts.
        mutating func next() async throws -> String? {
            var line: [UInt8] = []
            while let byte = try await byteIterator.next() {
                if byte == UInt8(ascii: "\n") { return Self.text(of: line) }
                guard line.count < maximumLength else { throw MCPClientError.tooLarge }
                line.append(byte)
            }
            return line.isEmpty ? nil : Self.text(of: line)
        }

        /// `line` as text, without the "\r" of a "\r\n" ending.
        private static func text(of line: [UInt8]) -> String {
            String(decoding: line.last == UInt8(ascii: "\r") ? line.dropLast() : line[...], as: UTF8.self)
        }
    }

    /// Starts reading at the first byte.
    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(byteIterator: bytes.makeAsyncIterator(), maximumLength: maximumLength)
    }
}
