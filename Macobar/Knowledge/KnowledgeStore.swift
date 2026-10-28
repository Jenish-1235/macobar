import Accelerate
import Foundation

/// One indexed passage of a document.
struct KnowledgeChunk: Codable, Sendable, Equatable {
    /// The document's full path.
    let path: String
    /// The passage's text.
    let text: String
}

/// A passage that matched a search.
struct KnowledgeMatch: Sendable, Equatable {
    /// The document's full path.
    let path: String
    /// The passage's text.
    let text: String
    /// Cosine similarity to the query, from -1 to 1; higher is closer.
    let score: Float
}

/// The index: every passage with its unit-length vector, kept as a JSON manifest plus a raw Float32 vector file.
struct KnowledgeStore: Sendable {
    /// Where the index lives by default.
    static let defaultFolderURL = URL.applicationSupportDirectory.appending(path: "macobar/knowledge")
    /// File holding the model, documents and passages.
    private static let manifestName = "manifest.json"
    /// File holding the vectors, one row of `dimension` floats per passage, in passage order.
    private static let vectorsName = "vectors.f32"

    /// What the manifest file holds.
    private struct Manifest: Codable {
        /// The embedding model the vectors came from.
        var model: String
        /// Floats per vector; 0 until the first vector is added.
        var dimension: Int
        /// Each indexed document's modification date when it was embedded, by path.
        var documents: [String: Date]
        /// Every passage, in vector order.
        var chunks: [KnowledgeChunk]
    }

    /// The model, documents and passages.
    private var manifest: Manifest
    /// Every passage's unit-length vector, row after row.
    private var vectors: [Float]

    /// An empty index for vectors from `model`.
    init(model: String) {
        manifest = Manifest(model: model, dimension: 0, documents: [:], chunks: [])
        vectors = []
    }

    /// The embedding model the vectors came from.
    var model: String { manifest.model }
    /// Each indexed document's modification date when it was embedded, by path.
    var documents: [String: Date] { manifest.documents }
    /// How many passages are indexed.
    var chunkCount: Int { manifest.chunks.count }

    /// The index saved in `folder`, or an empty one when there's none, it's damaged, or it came from another model.
    static func load(from folder: URL, model: String) -> KnowledgeStore {
        guard let manifestData = try? Data(contentsOf: folder.appending(path: manifestName)),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData),
              manifest.model == model,
              let expectedBytes = expectedVectorBytes(of: manifest),
              let vectorData = try? Data(contentsOf: folder.appending(path: vectorsName)),
              vectorData.count == expectedBytes
        else { return KnowledgeStore(model: model) }
        var store = KnowledgeStore(model: model)
        store.manifest = manifest
        store.vectors = [Float](repeating: 0, count: vectorData.count / MemoryLayout<Float>.size)
        _ = store.vectors.withUnsafeMutableBytes { vectorData.copyBytes(to: $0) }
        return store
    }

    /// The size the vector file must have for `manifest`, or nil when its dimension is negative, zero with passages (which would misalign later vectors) or the size overflows (a damaged file).
    private static func expectedVectorBytes(of manifest: Manifest) -> Int? {
        guard manifest.dimension > 0 || (manifest.dimension == 0 && manifest.chunks.isEmpty) else { return nil }
        let (floats, floatsOverflow) = manifest.chunks.count.multipliedReportingOverflow(by: manifest.dimension)
        let (bytes, bytesOverflow) = floats.multipliedReportingOverflow(by: MemoryLayout<Float>.size)
        return floatsOverflow || bytesOverflow ? nil : bytes
    }

    /// Writes the index into `folder`, creating it if needed; each file is replaced atomically.
    func save(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try vectors.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: folder.appending(path: Self.vectorsName), options: .atomic)
        try JSONEncoder().encode(manifest).write(to: folder.appending(path: Self.manifestName), options: .atomic)
    }

    /// Drops every passage of the documents at `paths`, in one pass over the vectors.
    mutating func removeDocuments(_ paths: Set<String>) {
        guard !paths.isEmpty else { return }
        let dimension = manifest.dimension
        var keptChunks: [KnowledgeChunk] = []
        var keptVectors: [Float] = []
        for (row, chunk) in manifest.chunks.enumerated() where !paths.contains(chunk.path) {
            keptChunks.append(chunk)
            keptVectors += vectors[(row * dimension)..<((row + 1) * dimension)]
        }
        manifest.chunks = keptChunks
        vectors = keptVectors
        for path in paths { manifest.documents[path] = nil }
    }

    /// Records the document at `path`, modified at `modified`, with its passages and their vectors (none for a document with no text).
    mutating func addDocument(path: String, modified: Date, chunks: [String], vectors newVectors: [[Float]]) throws {
        if manifest.dimension == 0, let first = newVectors.first { manifest.dimension = first.count }
        guard chunks.count == newVectors.count, newVectors.allSatisfy({ $0.count == manifest.dimension && !$0.isEmpty }) else {
            throw KnowledgeError.unexpectedReply(model: manifest.model)
        }
        for (text, vector) in zip(chunks, newVectors) {
            manifest.chunks.append(KnowledgeChunk(path: path, text: text))
            vectors += Self.unitLength(vector)
        }
        manifest.documents[path] = modified
    }

    /// The `limit` passages most similar to `query` by cosine similarity, best first.
    func search(_ query: [Float], limit: Int) -> [KnowledgeMatch] {
        let rows = manifest.chunks.count
        guard rows > 0, query.count == manifest.dimension else { return [] }
        var scores = [Float](repeating: 0, count: rows)
        // Rows are unit length, so one matrix-vector product gives every cosine similarity.
        vDSP_mmul(vectors, 1, Self.unitLength(query), 1, &scores, 1, vDSP_Length(rows), 1, vDSP_Length(manifest.dimension))
        return scores.indices.sorted { scores[$0] > scores[$1] }.prefix(limit).map { row in
            KnowledgeMatch(path: manifest.chunks[row].path, text: manifest.chunks[row].text, score: scores[row])
        }
    }

    /// `vector` scaled to length 1, or unchanged when it's all zeros.
    private static func unitLength(_ vector: [Float]) -> [Float] {
        let length = vDSP.sumOfSquares(vector).squareRoot()
        return length > 0 ? vDSP.divide(vector, length) : vector
    }
}
