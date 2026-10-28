import Foundation

/// Where the document index stands, for the model and the user.
struct KnowledgeStatus: Sendable, Equatable {
    /// Whether indexing is running now.
    let isIndexing: Bool
    /// Documents checked so far in the current or last run.
    let documentsDone: Int
    /// Documents found in the current or last run.
    let documentsTotal: Int
    /// Documents in the index.
    let indexedDocuments: Int
    /// Passages in the index.
    let indexedChunks: Int
    /// The folders being indexed, as paths.
    let folders: [String]
    /// Why the last run stopped early, if it did.
    let failure: String?

    /// One or two plain sentences saying what's indexed and what's happening.
    var summary: String {
        let folderList = folders.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: ", ")
        let indexed = "\(indexedDocuments) documents (\(indexedChunks) passages) from \(folderList) are searchable."
        if isIndexing { return "Indexing: \(documentsDone) of \(documentsTotal) documents checked. \(indexed)" }
        if let failure { return "Indexing stopped: \(failure) \(indexed)" }
        return indexed
    }
}
