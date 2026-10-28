import Foundation
import Synchronization

/// Every action Macie took, newest kept, in a JSON file shared by both agents, the tools and the History window.
struct ActivityLog: Sendable {
    /// Where the log lives by default.
    static let defaultFileURL = URL.applicationSupportDirectory.appending(path: "macobar/activity.json")
    /// Serialises read-modify-write cycles, since the chat, the scheduler and the History window write from different tasks.
    private static let fileLock = Mutex(())

    /// The JSON file holding the entries, oldest first; read on every call, since it's the shared state.
    private let fileURL: URL
    /// Most entries kept; older ones are dropped.
    private let capacity: Int

    /// Creates a log backed by `fileURL` keeping the newest `capacity` entries.
    init(fileURL: URL = Self.defaultFileURL, capacity: Int = 500) {
        self.fileURL = fileURL
        self.capacity = capacity
    }

    /// Every kept entry, newest first.
    func entries() throws -> [ActivityEntry] {
        try Self.fileLock.withLock { _ in try load().reversed() }
    }

    /// Adds `entry`, dropping the oldest beyond `capacity`.
    func append(_ entry: ActivityEntry) throws {
        try Self.fileLock.withLock { _ in
            try save(Array((try load() + [entry]).suffix(capacity)))
        }
    }

    /// Marks the entry named `id` as undone; does nothing if it was dropped meanwhile.
    func markUndone(id: UUID) throws {
        try Self.fileLock.withLock { _ in
            var entries = try load()
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index].isUndone = true
            try save(entries)
        }
    }

    /// Forgets every entry.
    func clear() throws {
        try Self.fileLock.withLock { _ in
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// The entries in the file, oldest first.
    private func load() throws -> [ActivityEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ActivityEntry].self, from: Data(contentsOf: fileURL))
    }

    /// Replaces the file with `entries` in one atomic write, creating its folder if needed.
    private func save(_ entries: [ActivityEntry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(entries).write(to: fileURL, options: .atomic)
    }
}
