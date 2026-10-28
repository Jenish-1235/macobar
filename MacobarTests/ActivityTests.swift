import Foundation
import Testing

/// Verifies undo planning and inference, the activity log file, and grouping by day.
struct ActivityTests {
    /// A Gregorian calendar in GMT, so results don't depend on the machine's time zone.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// A fresh folder under the temporary directory.
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ActivityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The moment on `day` October 2026 at `hour`:00 GMT.
    private func october(_ day: Int, _ hour: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour)))
    }

    @Test("A move is undone by moving the item back")
    func movedReversal() {
        let original = URL(fileURLWithPath: "/Users/me/a.pdf")
        let current = URL(fileURLWithPath: "/Users/me/Archive/a.pdf")
        #expect(UndoStep.moved(from: original, to: current).reversal == .move(from: current, to: original))
    }

    @Test("A copy is undone by trashing the copy")
    func copiedReversal() {
        let copy = URL(fileURLWithPath: "/Users/me/Archive/a.pdf")
        #expect(UndoStep.copied(to: copy).reversal == .trash(copy))
    }

    @Test("A new file is undone by trashing it")
    func wroteFileReversal() {
        let file = URL(fileURLWithPath: "/Users/me/notes.txt")
        #expect(UndoStep.wroteFile(path: file).reversal == .trash(file))
    }

    @Test("A new folder is undone by trashing it only while empty")
    func createdFolderReversal() {
        let folder = URL(fileURLWithPath: "/Users/me/Invoices")
        #expect(UndoStep.createdFolder(path: folder).reversal == .trashEmptyFolder(folder))
    }

    @Test("Trashing is undone by putting the item back from the Trash")
    func trashedReversal() {
        let original = URL(fileURLWithPath: "/Users/me/a.pdf")
        let trashURL = URL(fileURLWithPath: "/Users/me/.Trash/a.pdf")
        #expect(UndoStep.trashed(original: original, trashURL: trashURL).reversal == .putBack(from: trashURL, to: original))
    }

    @Test("Creating a folder infers a created folder, with ~ expanded")
    func infersCreatedFolder() {
        let input = ToolInput(["action": "create_folder", "path": "~/Invoices"])
        let expected = URL(fileURLWithPath: NSHomeDirectory() + "/Invoices")
        #expect(UndoStep.inferred(toolName: "manage_file", input: input, output: "Created folder x.") == .createdFolder(path: expected))
    }

    @Test("Writing a new file infers a written file; overwriting can't be undone")
    func infersWrittenFile() {
        let fresh = ToolInput(["action": "write_text", "path": "/tmp/notes.txt", "text": "Hi"])
        let overwrite = ToolInput(["action": "write_text", "path": "/tmp/notes.txt", "text": "Hi", "overwrite": true])
        #expect(UndoStep.inferred(toolName: "manage_file", input: fresh, output: "Saved /tmp/notes.txt.") == .wroteFile(path: URL(fileURLWithPath: "/tmp/notes.txt")))
        #expect(UndoStep.inferred(toolName: "manage_file", input: overwrite, output: "Saved /tmp/notes.txt.") == nil)
    }

    @Test("A move takes its final place from the result, even into a folder")
    func infersMove() {
        let input = ToolInput(["action": "move", "path": "/Users/me/a.pdf", "destination": "/Users/me/Archive"])
        let step = UndoStep.inferred(toolName: "manage_file", input: input, output: "Moved to /Users/me/Archive/a.pdf.")
        #expect(step == .moved(from: URL(fileURLWithPath: "/Users/me/a.pdf"), to: URL(fileURLWithPath: "/Users/me/Archive/a.pdf")))
    }

    @Test("A move keeps a destination path that holds a line break")
    func infersMoveWithLineBreak() {
        let input = ToolInput(["action": "move", "path": "/Users/me/a.pdf", "destination": "/Users/me/a.\nb.pdf"])
        let step = UndoStep.inferred(toolName: "manage_file", input: input, output: "Moved to /Users/me/a.\nb.pdf.")
        #expect(step == .moved(from: URL(fileURLWithPath: "/Users/me/a.pdf"), to: URL(fileURLWithPath: "/Users/me/a.\nb.pdf")))
    }

    @Test("A copy takes its final place from the result")
    func infersCopy() {
        let input = ToolInput(["action": "copy", "path": "/Users/me/a.pdf", "destination": "/Users/me/b.pdf"])
        let step = UndoStep.inferred(toolName: "manage_file", input: input, output: "Copied to /Users/me/b.pdf.")
        #expect(step == .copied(to: URL(fileURLWithPath: "/Users/me/b.pdf")))
    }

    @Test("Trashing is undoable only when the result says where the item went")
    func infersTrash() {
        let input = ToolInput(["action": "trash", "path": "/Users/me/a.pdf"])
        let located = "Moved /Users/me/a.pdf to the Trash.\n\(UndoStep.trashLocationPrefix)/Users/me/.Trash/a 10.32.11.pdf."
        let step = UndoStep.inferred(toolName: "manage_file", input: input, output: located)
        #expect(step == .trashed(original: URL(fileURLWithPath: "/Users/me/a.pdf"), trashURL: URL(fileURLWithPath: "/Users/me/.Trash/a 10.32.11.pdf")))
        #expect(UndoStep.inferred(toolName: "manage_file", input: input, output: "Moved /Users/me/a.pdf to the Trash.") == nil)
    }

    @Test("Other tools and unreadable results infer nothing")
    func infersNothingElse() {
        let move = ToolInput(["action": "move", "path": "/Users/me/a.pdf", "destination": "/Users/me/b.pdf"])
        #expect(UndoStep.inferred(toolName: "open_file", input: ToolInput(["path": "/Users/me/a.pdf"]), output: "Opened /Users/me/a.pdf.") == nil)
        #expect(UndoStep.inferred(toolName: "manage_file", input: move, output: "Done.") == nil)
    }

    @Test("Undo refuses to move an item back over something already there")
    func refusesOccupiedPlace() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appending(path: "a.txt")
        let current = folder.appending(path: "b.txt")
        try "new".write(to: original, atomically: true, encoding: .utf8)
        try "moved".write(to: current, atomically: true, encoding: .utf8)
        #expect(throws: UndoError.occupied(original)) { try UndoRunner.undo(.moved(from: original, to: current)) }
        #expect(try String(contentsOf: current, encoding: .utf8) == "moved")
    }

    @Test("Undo moves an item back to where it was")
    func movesBack() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appending(path: "a.txt")
        let current = folder.appending(path: "b.txt")
        try "moved".write(to: current, atomically: true, encoding: .utf8)
        _ = try UndoRunner.undo(.moved(from: original, to: current))
        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(!FileManager.default.fileExists(atPath: current.path))
    }

    @Test("Undo refuses when the item is gone")
    func refusesMissingItem() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let current = folder.appending(path: "b.txt")
        #expect(throws: UndoError.missing(current)) { try UndoRunner.undo(.moved(from: folder.appending(path: "a.txt"), to: current)) }
    }

    @Test("Undo refuses to put an item back when its folder is gone")
    func refusesMissingFolder() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appending(path: "Gone/a.txt")
        let trashed = folder.appending(path: "a.txt")
        try "trashed".write(to: trashed, atomically: true, encoding: .utf8)
        #expect(throws: UndoError.missing(original.deletingLastPathComponent())) { try UndoRunner.undo(.trashed(original: original, trashURL: trashed)) }
        #expect(FileManager.default.fileExists(atPath: trashed.path))
    }

    @Test("The log lists newest first, keeps the newest entries, and survives a reload")
    func logRoundTripAndTrimming() throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "ActivityTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let log = ActivityLog(fileURL: fileURL, capacity: 3)
        #expect(try log.entries().isEmpty)

        let entries = try (1...4).map { ActivityEntry(toolName: "open_app", activity: "Opening app \($0)", outcome: .succeeded, result: "Opened.", date: try october(28, $0)) }
        for entry in entries { try log.append(entry) }
        #expect(try ActivityLog(fileURL: fileURL, capacity: 3).entries() == entries.suffix(3).reversed())
    }

    @Test("Marking an entry undone stops it being undoable, and clearing empties the log")
    func markUndoneAndClear() throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "ActivityTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let log = ActivityLog(fileURL: fileURL)
        let entry = ActivityEntry(toolName: "manage_file", activity: "Creating folder “x”", outcome: .succeeded, undoStep: .createdFolder(path: URL(fileURLWithPath: "/tmp/x")))
        try log.append(entry)
        #expect(try log.entries().first?.isUndoable == true)

        try log.markUndone(id: entry.id)
        #expect(try log.entries().first?.isUndoable == false)

        try log.clear()
        #expect(try log.entries().isEmpty)
    }

    @Test("Long results are cut to the kept length")
    func resultIsCut() {
        let entry = ActivityEntry(toolName: "read_file", activity: "Reading", outcome: .failed, result: String(repeating: "x", count: 1_000))
        #expect(entry.result.count == ActivityEntry.resultLength)
    }

    @Test("Entries are grouped by day, newest day first")
    func groupsByDay() throws {
        let entries = [
            ActivityEntry(toolName: "a", activity: "Third", outcome: .succeeded, date: try october(28, 15)),
            ActivityEntry(toolName: "a", activity: "Second", outcome: .succeeded, date: try october(28, 9)),
            ActivityEntry(toolName: "a", activity: "First", outcome: .declined, date: try october(27, 22)),
        ]
        let days = ActivityDay.grouping(entries, in: calendar)
        let expectedDays = [try october(28, 0), try october(27, 0)]
        #expect(days.map(\.date) == expectedDays)
        #expect(days.map { $0.entries.map(\.activity) } == [["Third", "Second"], ["First"]])
    }
}
