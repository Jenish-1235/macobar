import Foundation
import Synchronization

/// Scheduled tasks kept in a JSON file, shared by the schedule tools and the scheduler.
struct ScheduledTaskStore: Sendable {
    /// Where the tasks live by default.
    static let defaultFileURL = URL.applicationSupportDirectory.appending(path: "macobar/scheduled-tasks.json")
    /// Serialises read-modify-write cycles, since tools and the scheduler change the file from different tasks.
    private static let fileLock = Mutex(())

    /// The JSON file holding the tasks; read on every call, since it's the shared state.
    private let fileURL: URL

    /// Creates a store backed by `fileURL`.
    init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// Every task, soonest first; none before the first is added.
    func tasks() throws -> [ScheduledTask] {
        try Self.fileLock.withLock { _ in try load() }
    }

    /// Adds a task running `prompt` at `firstRun`, then by `repeatRule`, and returns it.
    func add(prompt: String, firstRun: Date, repeatRule: RepeatRule) throws -> ScheduledTask {
        try Self.fileLock.withLock { _ in
            var tasks = try load()
            let task = ScheduledTask(id: Self.nextID(after: tasks), prompt: prompt, nextRun: firstRun, repeatRule: repeatRule)
            tasks.append(task)
            try save(tasks)
            return task
        }
    }

    /// Removes the task named `id` and returns it, or nil when there's none.
    func remove(id: String) throws -> ScheduledTask? {
        try Self.fileLock.withLock { _ in
            var tasks = try load()
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
            let task = tasks.remove(at: index)
            try save(tasks)
            return task
        }
    }

    /// Replaces the stored task with the same id; does nothing if it was removed meanwhile.
    func update(_ task: ScheduledTask) throws {
        try Self.fileLock.withLock { _ in
            var tasks = try load()
            guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
            tasks[index] = task
            try save(tasks)
        }
    }

    /// The tasks in the file, soonest first.
    private func load() throws -> [ScheduledTask] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ScheduledTask].self, from: Data(contentsOf: fileURL)).sorted { $0.nextRun < $1.nextRun }
    }

    /// One more than the highest numbered id in `tasks`, e.g. "t4" after "t3".
    private static func nextID(after tasks: [ScheduledTask]) -> String {
        let highest = tasks.compactMap { Int($0.id.dropFirst()) }.filter { $0 < Int.max }.max() ?? 0
        return "t\(highest + 1)"
    }

    /// Replaces the file with `tasks` in one atomic write, creating its folder if needed.
    private func save(_ tasks: [ScheduledTask]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(tasks).write(to: fileURL, options: .atomic)
    }
}
