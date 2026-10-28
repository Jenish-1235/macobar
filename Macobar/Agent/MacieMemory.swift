import Foundation

/// A durable fact Macie keeps about the user.
struct Memory: Codable, Sendable, Equatable {
    /// Short stable name the model refers to it by, e.g. "m3".
    let id: String
    /// The fact itself, on one line.
    let text: String
    /// When it was remembered.
    let added: Date
}

/// Facts about the user kept in a JSON file, shared by every conversation and launch.
struct MacieMemory: Sendable {
    /// Longest fact worth keeping, in characters.
    static let maximumLength = 300
    /// Most facts kept; past this, one must be forgotten first.
    static let maximumCount = 100
    /// Where the facts live by default.
    static let defaultFileURL = URL.applicationSupportDirectory.appending(path: "macobar/memory.json")

    /// The JSON file holding the facts; read on every call, since it's the shared state.
    private let fileURL: URL

    /// Creates a store backed by `fileURL`.
    init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// Every fact, oldest first; facts that `add` would refuse (edited into the file by hand or by another program) are left out, so the file can't add instructions of its own.
    func entries() throws -> [Memory] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let memories = try decoder.decode([Memory].self, from: Data(contentsOf: fileURL)).compactMap(Self.wellFormed)
        return Array(memories.prefix(Self.maximumCount))
    }

    /// Keeps `text` as one line with single spaces, returning the existing fact when it's already kept.
    func add(_ text: String) throws -> Memory {
        let line = Self.oneLine(text)
        guard !line.isEmpty else { throw MacieMemoryError.empty }
        guard line.count <= Self.maximumLength else { throw MacieMemoryError.tooLong }
        var memories = try entries()
        if let existing = memories.first(where: { $0.text == line }) { return existing }
        guard memories.count < Self.maximumCount else { throw MacieMemoryError.full }
        let memory = Memory(id: Self.nextID(after: memories), text: line, added: .now)
        memories.append(memory)
        try save(memories)
        return memory
    }

    /// Forgets the fact named `id` and returns it.
    func remove(id: String) throws -> Memory {
        var memories = try entries()
        guard let index = memories.firstIndex(where: { $0.id == id }) else { throw MacieMemoryError.unknownID(id) }
        let memory = memories.remove(at: index)
        try save(memories)
        return memory
    }

    /// One more than the highest numbered id in `memories`, e.g. "m4" after "m3".
    private static func nextID(after memories: [Memory]) -> String {
        let highest = memories.compactMap { Int($0.id.dropFirst()) }.filter { $0 < Int.max }.max() ?? 0
        return "m\(highest + 1)"
    }

    /// `text` on one line with single spaces.
    private static func oneLine(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// `memory` with its text on one line, or nil when its id isn't "m" and a number or its text is blank or too long.
    private static func wellFormed(_ memory: Memory) -> Memory? {
        let text = oneLine(memory.text)
        guard memory.id.first == "m", memory.id.dropFirst().allSatisfy(\.isASCII), Int(memory.id.dropFirst()) != nil,
              !text.isEmpty, text.count <= maximumLength else { return nil }
        return Memory(id: memory.id, text: text, added: memory.added)
    }

    /// Replaces the file with `memories` in one atomic write, creating its folder if needed.
    private func save(_ memories: [Memory]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(memories).write(to: fileURL, options: .atomic)
    }
}

/// Why a fact couldn't be remembered or forgotten, in words the model can act on.
enum MacieMemoryError: LocalizedError, Equatable {
    /// The fact was blank.
    case empty
    /// The fact is longer than `MacieMemory.maximumLength`.
    case tooLong
    /// `MacieMemory.maximumCount` facts are already kept.
    case full
    /// No fact has this id.
    case unknownID(String)

    /// The message, for `localizedDescription`.
    var errorDescription: String? {
        switch self {
        case .empty: "The fact is empty. Pass the fact to remember as one short sentence."
        case .tooLong: "The fact is longer than \(MacieMemory.maximumLength) characters. Shorten it to one sentence."
        case .full: "Memory is full (\(MacieMemory.maximumCount) facts). Forget an outdated one first, or ask the user which to drop."
        case .unknownID(let id): "No memory has the id \"\(id)\". Use an id from the list in your instructions, e.g. \"m3\"."
        }
    }
}
