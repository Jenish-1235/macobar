import Foundation

/// Finds passages in the user's documents by meaning, using the index built on this Mac.
struct SearchKnowledgeTool: Tool {
    /// Results returned when the model doesn't say.
    private static let defaultLimit = 5
    /// Most results returned at once.
    private static let maximumLimit = 10
    /// Longest excerpt shown per result, in characters.
    private static let excerptLength = 300

    /// The index searched.
    private let indexer: KnowledgeIndexer

    /// Name the model calls it by.
    let name = "search_documents"
    /// When to call it and what it returns.
    let description = """
        Searches the user's documents by meaning in a private on-device index. Call it to find a document from a \
        description rather than its exact words, then read_file a path for the full text. Returns passages with path, \
        score (higher is closer) and excerpt. If nothing is indexed or the embeddings server is down, use search_files.
        """

    /// Creates the tool, searching `indexer`.
    init(indexer: KnowledgeIndexer) {
        self.indexer = indexer
    }

    /// Takes the description to search for and how many results to return.
    var parameters: JSONValue {
        Schema.object([
            "query": Schema.string("What the document is about, in plain words."),
            "limit": Schema.integer("1 to 10. Default 5."),
        ], required: ["query"])
    }

    /// Its result carries outside text the model will read, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Names the search.
    func activity(for input: ToolInput) -> String {
        "Searching documents for “\(input.string("query") ?? "")”"
    }

    /// Embeds the query and lists the closest passages.
    func run(_ input: ToolInput) async throws -> String {
        let query = try input.requiredString("query")
        let limit = min(max(input.integer("limit") ?? Self.defaultLimit, 1), Self.maximumLimit)
        let matches: [KnowledgeMatch]
        do {
            matches = try await indexer.search(query, limit: limit)
        } catch {
            throw ToolError("\(error.localizedDescription) Use search_files for now.")
        }
        let status = await indexer.status
        guard !matches.isEmpty else {
            let nextStep = status.isIndexing ? "Indexing is running" : "Call index_documents to build the index"
            return "Nothing is indexed yet. \(status.summary) \(nextStep); use search_files for now."
        }
        let results = matches.enumerated().map { number, match in
            "\(number + 1). \(match.path) (score \(String(format: "%.2f", match.score)))\n   \(excerpt(of: match.text))"
        }
        let note = status.isIndexing ? "\nIndexing is still running, so some documents may be missing." : ""
        return results.joined(separator: "\n") + note
    }

    /// The start of `text`, cut at `excerptLength` characters.
    private func excerpt(of text: String) -> String {
        text.count > Self.excerptLength ? text.prefix(Self.excerptLength - 1) + "…" : text
    }
}

/// Builds or refreshes the index search_documents uses.
struct IndexDocumentsTool: Tool {
    /// The index built.
    private let indexer: KnowledgeIndexer

    /// Name the model calls it by.
    let name = "index_documents"
    /// When to call it and what it returns.
    let description = """
        Builds or refreshes, in the background, the private index search_documents uses; only changed files are \
        re-read. Call it when the user asks to index documents, add folders, or check progress. Returns the status.
        """

    /// Creates the tool, building `indexer`.
    init(indexer: KnowledgeIndexer) {
        self.indexer = indexer
    }

    /// Takes the folders to index, optionally.
    var parameters: JSONValue {
        Schema.object([
            "folders": Schema.strings("Replaces the indexed folders (at first ~/Documents, ~/Desktop). Omit to keep them."),
        ])
    }

    /// Indexing a private folder (Library or a hidden one) asks every time, since search_documents then shows its text without asking; other folders index freely.
    func risk(for input: ToolInput) -> ToolRisk {
        let folders = input.strings("folders").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        return folders.contains(where: ProtectedLocations.isPrivate) ? .confirmEveryTime : .none
    }

    /// Describes the indexing.
    func activity(for input: ToolInput) -> String { "Indexing documents" }

    /// Checks the folders, starts indexing if it isn't running, and reports the status.
    func run(_ input: ToolInput) async throws -> String {
        let paths = input.strings("folders")
        let folders = paths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL }
        for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true {
            throw ToolError("\(folder.path) isn't a folder. Pass existing folders, e.g. \"~/Documents\", or use search_files to find one.")
        }
        let status = await indexer.start(folders: folders.isEmpty ? nil : folders)
        return "\(status.summary) Indexing runs in the background; call index_documents again to check progress."
    }
}
