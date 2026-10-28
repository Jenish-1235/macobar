import Foundation

/// Keeps the document index up to date in the background and searches it; nothing leaves the Mac.
actor KnowledgeIndexer {
    /// Documents embedded between saves, so a quit mid-run loses little work.
    private static let saveInterval = 100

    /// Where the index is saved.
    private let storeFolder: URL
    /// The server address, model and folders to use.
    private let settings = KnowledgeSettings()
    /// The index, read from disk on first use.
    private var store: KnowledgeStore?
    /// The indexing run in progress, if any.
    private var indexing: Task<Void, Never>?
    /// Documents checked and found in the current or last run.
    private var progress = (done: 0, total: 0)
    /// Why the last run stopped early, if it did.
    private var failure: String?

    /// Creates an indexer saving into `storeFolder`.
    init(storeFolder: URL = KnowledgeStore.defaultFolderURL) {
        self.storeFolder = storeFolder
    }

    /// Where the index stands now.
    var status: KnowledgeStatus {
        let store = openStore()
        return KnowledgeStatus(
            isIndexing: indexing != nil,
            documentsDone: progress.done,
            documentsTotal: progress.total,
            indexedDocuments: store.documents.count,
            indexedChunks: store.chunkCount,
            folders: settings.folders.map(\.path),
            failure: failure
        )
    }

    /// Starts indexing `folders` (remembered for later runs) or the saved folders, unless a run is already going; returns the status.
    func start(folders: [URL]? = nil) -> KnowledgeStatus {
        if let folders { settings.setFolders(folders) }
        if indexing == nil {
            failure = nil
            let folders = settings.folders
            indexing = Task { await index(folders) }
        }
        return status
    }

    /// Brings an existing index up to date, e.g. at launch; does nothing if the user never indexed.
    func refreshIfIndexed() {
        guard !openStore().documents.isEmpty else { return }
        _ = start()
    }

    /// Cancels the run in progress; what's embedded so far is saved.
    func stop() {
        indexing?.cancel()
    }

    /// The `limit` passages closest in meaning to `query`; empty when nothing is indexed.
    func search(_ query: String, limit: Int) async throws -> [KnowledgeMatch] {
        guard openStore().chunkCount > 0 else { return [] }
        let vectors = try await EmbeddingsClient(serverAddress: settings.serverAddress, model: settings.model).embed([query])
        return store?.search(vectors.first ?? [], limit: limit) ?? []
    }

    /// The index for the current model, loading it from disk when it isn't loaded or the model changed.
    private func openStore() -> KnowledgeStore {
        if let store, store.model == settings.model { return store }
        let loaded = KnowledgeStore.load(from: storeFolder, model: settings.model)
        store = loaded
        return loaded
    }

    /// Drops deleted and changed documents, then embeds every document not yet indexed, saving as it goes.
    private func index(_ folders: [URL]) async {
        defer { indexing = nil }
        let client = EmbeddingsClient(serverAddress: settings.serverAddress, model: settings.model)
        let found: [String: Date]
        do {
            found = try await DocumentFinder.documents(in: folders)
        } catch {
            if !Task.isCancelled { failure = error.localizedDescription }
            return
        }
        let indexed = openStore().documents
        let outdated = Set(indexed.keys.filter { found[$0] != indexed[$0] })
        let pending = found.filter { indexed[$0.key] != $0.value }.sorted { $0.key < $1.key }
        progress = (found.count - pending.count, found.count)
        guard !outdated.isEmpty || !pending.isEmpty else { return }
        store?.removeDocuments(outdated)
        for (path, modified) in pending {
            guard !Task.isCancelled else { break }
            do {
                let chunks = await Self.passages(of: URL(fileURLWithPath: path))
                let vectors = try await client.embed(chunks)
                try store?.addDocument(path: path, modified: modified, chunks: chunks, vectors: vectors)
            } catch {
                if !Task.isCancelled { failure = error.localizedDescription }
                break
            }
            progress.done += 1
            if progress.done % Self.saveInterval == 0 { save() }
        }
        save()
    }

    /// The passages of the document at `url`, read and split off the indexer's actor so searches aren't held up.
    @concurrent private static func passages(of url: URL) async -> [String] {
        TextChunker.chunks(of: await DocumentText.text(of: url))
    }

    /// Writes the index to disk, noting a failure instead of throwing.
    private func save() {
        do {
            try store?.save(to: storeFolder)
        } catch {
            failure = "Couldn't save the index: \(error.localizedDescription)"
        }
    }
}
