import Foundation
import Testing

/// Verifies how documents are split, ranked, stored and embedded for knowledge search.
struct KnowledgeTests {
    /// A store folder that doesn't exist yet, in the temporary directory.
    private let folder = FileManager.default.temporaryDirectory.appending(path: "KnowledgeTests-\(UUID().uuidString)")

    /// "w0 w1 … w(count-1)", a text whose words are easy to find again.
    private func numberedWords(_ count: Int) -> String {
        (0..<count).map { "w\($0)" }.joined(separator: " ")
    }

    @Test("Short text is one passage with whitespace collapsed")
    func shortTextIsOneChunk() {
        #expect(TextChunker.chunks(of: "  Renewal fee:\n\n  £400 a year.  ") == ["Renewal fee: £400 a year."])
    }

    @Test("Blank text has no passages")
    func blankTextHasNoChunks() {
        #expect(TextChunker.chunks(of: " \n\t ").isEmpty)
    }

    @Test("Long text splits into bounded passages that overlap and cover every word")
    func longTextOverlaps() {
        let chunks = TextChunker.chunks(of: numberedWords(2_000))
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= TextChunker.chunkLength })
        #expect(chunks.first?.hasPrefix("w0 ") == true)
        #expect(chunks.last?.hasSuffix(" w1999") == true)
        for (previous, next) in zip(chunks, chunks.dropFirst()) {
            let firstWord = String(next.prefix { $0 != " " })
            #expect(previous.split(separator: " ").contains(Substring(firstWord)))
        }
    }

    @Test("Passages never cut a word in half")
    func cutsBetweenWords() {
        let words = Set(numberedWords(2_000).split(separator: " "))
        let chunkWords = TextChunker.chunks(of: numberedWords(2_000)).flatMap { $0.split(separator: " ") }
        #expect(chunkWords.allSatisfy(words.contains))
    }

    @Test("Search ranks passages by cosine similarity, ignoring vector length")
    func ranksByCosine() throws {
        var store = KnowledgeStore(model: "test")
        try store.addDocument(path: "/a.txt", modified: .now, chunks: ["east", "north"], vectors: [[10, 0], [0, 1]])
        try store.addDocument(path: "/b.txt", modified: .now, chunks: ["north-east"], vectors: [[1, 1]])
        let matches = store.search([0, 3], limit: 2)
        #expect(matches.map(\.text) == ["north", "north-east"])
        #expect(abs((matches.first?.score ?? 0) - 1) < 0.0001)
        #expect(abs((matches.last?.score ?? 0) - 0.7071) < 0.0001)
    }

    @Test("Removing a document drops only its passages")
    func removesDocuments() throws {
        var store = KnowledgeStore(model: "test")
        try store.addDocument(path: "/a.txt", modified: .now, chunks: ["east"], vectors: [[1, 0]])
        try store.addDocument(path: "/b.txt", modified: .now, chunks: ["north"], vectors: [[0, 1]])
        store.removeDocuments(["/a.txt"])
        #expect(Array(store.documents.keys) == ["/b.txt"])
        #expect(store.search([1, 0], limit: 5).map(\.text) == ["north"])
    }

    @Test("Vectors of the wrong size are refused")
    func refusesMismatchedVectors() throws {
        var store = KnowledgeStore(model: "test")
        try store.addDocument(path: "/a.txt", modified: .now, chunks: ["east"], vectors: [[1, 0]])
        #expect(throws: KnowledgeError.unexpectedReply(model: "test")) {
            try store.addDocument(path: "/b.txt", modified: .now, chunks: ["up"], vectors: [[0, 0, 1]])
        }
    }

    @Test("A saved index loads back with its dates, passages and vectors")
    func storeRoundTrip() throws {
        let modified = Date(timeIntervalSinceReferenceDate: 800_000_000.123_456)
        defer { try? FileManager.default.removeItem(at: folder) }
        var store = KnowledgeStore(model: "test")
        try store.addDocument(path: "/a.txt", modified: modified, chunks: ["east", "north"], vectors: [[1, 0], [0, 2]])
        try store.save(to: folder)
        let loaded = KnowledgeStore.load(from: folder, model: "test")
        #expect(loaded.documents == ["/a.txt": modified])
        #expect(loaded.chunkCount == 2)
        #expect(loaded.search([0, 1], limit: 1) == store.search([0, 1], limit: 1))
    }

    @Test("An index made with another model, or none at all, loads empty")
    func loadsEmptyForOtherModel() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        var store = KnowledgeStore(model: "old")
        try store.addDocument(path: "/a.txt", modified: .now, chunks: ["east"], vectors: [[1, 0]])
        try store.save(to: folder)
        #expect(KnowledgeStore.load(from: folder, model: "new").chunkCount == 0)
        #expect(KnowledgeStore.load(from: folder.appending(path: "missing"), model: "old").chunkCount == 0)
    }

    @Test("Embeddings replies are decoded in input order")
    func decodesEmbeddings() throws {
        let reply = """
            {"object":"list","model":"nomic","data":[
            {"object":"embedding","index":1,"embedding":[0.5,-1]},
            {"object":"embedding","index":0,"embedding":[1,0.25]}]}
            """
        #expect(try EmbeddingsClient.vectors(from: Data(reply.utf8)) == [[1, 0.25], [0.5, -1]])
    }

    @Test("An unreachable server says how to start one")
    func unreachableServerMessage() throws {
        let address = try #require(URL(string: KnowledgeSettings.defaultServerAddress))
        let message = KnowledgeError.serverUnavailable(address).localizedDescription
        #expect(message.contains("Start LM Studio's server and load an embedding model"))
    }
}
