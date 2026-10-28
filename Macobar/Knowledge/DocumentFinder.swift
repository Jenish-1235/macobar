import Foundation

/// Finds the documents worth indexing in the user's chosen folders.
enum DocumentFinder {
    /// Largest file indexed, in bytes.
    static let sizeLimit = 20_000_000
    /// Folders never descended into: code dependencies, repositories and app data.
    private static let skippedFolderNames: Set = ["node_modules", ".git", "Library"]
    /// File details read while walking.
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .ubiquitousItemDownloadingStatusKey,
    ]

    /// Each indexable file's path and modification date; throws if a folder can't be listed, which would otherwise look empty and drop its documents.
    @concurrent static func documents(in folders: [URL]) async throws -> [String: Date] {
        var documents: [String: Date] = [:]
        for folder in folders {
            guard (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil,
                  let walker = FileManager.default.enumerator(
                      at: folder, includingPropertiesForKeys: Array(resourceKeys), options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  )
            else { throw KnowledgeError.folderUnreadable(folder) }
            while let url = walker.nextObject() as? URL {
                try Task.checkCancellation()
                guard let values = try? url.resourceValues(forKeys: resourceKeys) else { continue }
                if values.isDirectory == true, skippedFolderNames.contains(url.lastPathComponent) {
                    walker.skipDescendants()
                } else if isIndexable(url, values), let modified = values.contentModificationDate {
                    documents[url.standardizedFileURL.path] = modified
                }
            }
        }
        return documents
    }

    /// Whether `url` is a supported, small enough file whose contents are already on this Mac (reading an iCloud placeholder would download it).
    private static func isIndexable(_ url: URL, _ values: URLResourceValues) -> Bool {
        values.isRegularFile == true
            && DocumentText.supportedExtensions.contains(url.pathExtension.lowercased())
            && (values.fileSize ?? 0) <= sizeLimit
            && values.ubiquitousItemDownloadingStatus != .notDownloaded
    }
}
