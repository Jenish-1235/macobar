import Foundation

/// Where knowledge search gets its embeddings and which folders it indexes, kept in preferences.
struct KnowledgeSettings: Sendable {
    /// LM Studio's local server, used until the user sets another.
    static let defaultServerAddress = "http://localhost:1234/v1"
    /// LM Studio's bundled embedding model, used until the user sets another.
    static let defaultModel = "text-embedding-nomic-embed-text-v1.5"
    /// Preferences key holding the embeddings server address.
    private static let serverAddressKey = "knowledgeServerAddress"
    /// Preferences key holding the embedding model's name.
    private static let modelKey = "knowledgeEmbeddingModel"
    /// Preferences key holding the indexed folders' paths.
    private static let foldersKey = "knowledgeFolders"

    /// Hosts document text may be sent to: this Mac only, so the index never leaks off the device.
    private static let localHosts: Set = ["localhost", "127.0.0.1", "::1"]

    /// The OpenAI-compatible server on this Mac that turns text into vectors; anything else falls back to the default.
    var serverAddress: URL {
        let address = UserDefaults.standard.string(forKey: Self.serverAddressKey) ?? Self.defaultServerAddress
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased()),
              let host = url.host(), Self.localHosts.contains(host.lowercased())
        else {
            return URL(string: Self.defaultServerAddress) ?? URL(fileURLWithPath: "/")
        }
        return url
    }

    /// The embedding model the server runs.
    var model: String {
        UserDefaults.standard.string(forKey: Self.modelKey) ?? Self.defaultModel
    }

    /// The folders to index; ~/Documents and ~/Desktop until the user picks others.
    var folders: [URL] {
        guard let paths = UserDefaults.standard.stringArray(forKey: Self.foldersKey), !paths.isEmpty else {
            return [URL.documentsDirectory, URL.desktopDirectory]
        }
        return paths.map { URL(fileURLWithPath: $0) }
    }

    /// Indexes `folders` from now on.
    func setFolders(_ folders: [URL]) {
        UserDefaults.standard.set(folders.map(\.path), forKey: Self.foldersKey)
    }
}
