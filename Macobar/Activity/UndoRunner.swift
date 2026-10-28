import Foundation

/// Carries out an `UndoStep`'s reversal, refusing when the files no longer match what Macie left.
enum UndoRunner {
    /// Reverses `step` and returns what was done.
    static func undo(_ step: UndoStep) throws -> String {
        let files = FileManager.default
        // The log is a file on disk, so a step is checked like any file change before it's carried out.
        for item in step.reversal.items {
            guard ProtectedLocations.refusal(forChanging: item) == nil else { throw UndoError.protected(item) }
        }
        switch step.reversal {
        case .move(let source, let destination):
            guard files.fileExists(atPath: source.path) else { throw UndoError.missing(source) }
            guard !files.fileExists(atPath: destination.path) else { throw UndoError.occupied(destination) }
            try files.moveItem(at: source, to: destination)
            return "Moved it back to \(destination.path)."
        case .putBack(let source, let destination):
            let folder = destination.deletingLastPathComponent()
            guard files.fileExists(atPath: folder.path) else { throw UndoError.missing(folder) }
            guard !files.fileExists(atPath: destination.path) else { throw UndoError.occupied(destination) }
            do {
                try files.moveItem(at: source, to: destination)
            } catch CocoaError.fileNoSuchFile, CocoaError.fileReadNoSuchFile {
                throw UndoError.missing(source)
            } catch {
                throw UndoError.lockedInTrash(destination.lastPathComponent)
            }
            return "Put \(destination.path) back from the Trash."
        case .trash(let item):
            guard files.fileExists(atPath: item.path) else { throw UndoError.missing(item) }
            try files.trashItem(at: item, resultingItemURL: nil)
            return "Moved \(item.path) to the Trash."
        case .trashEmptyFolder(let folder):
            guard files.fileExists(atPath: folder.path) else { throw UndoError.missing(folder) }
            guard try files.contentsOfDirectory(atPath: folder.path).isEmpty else { throw UndoError.notEmpty(folder) }
            try files.trashItem(at: folder, resultingItemURL: nil)
            return "Moved the folder \(folder.path) to the Trash."
        }
    }
}

/// Why an undo was refused, with what the user can do instead.
enum UndoError: LocalizedError, Equatable {
    /// The item Macie left, or the folder it would go back to, is gone.
    case missing(URL)
    /// Something else now sits where the item would go back to.
    case occupied(URL)
    /// The folder Macie created has things in it now.
    case notEmpty(URL)
    /// macOS wouldn't let macobar take the named item out of the Trash.
    case lockedInTrash(String)
    /// The step would change a protected location (a system folder, secrets, login items or macobar's own data).
    case protected(URL)

    /// The message, for `localizedDescription`.
    var errorDescription: String? {
        switch self {
        case .missing(let url): "\(url.path) isn't there any more, so this can't be undone. It may have been moved or deleted since."
        case .occupied(let url): "Something is already at \(url.path). Move or rename it, then undo again."
        case .notEmpty(let url): "\(url.path) has things in it now, so it wasn't trashed. Move them out first, or trash the folder in Finder."
        case .lockedInTrash(let name): "macOS didn't let macobar take “\(name)” out of the Trash. Open the Trash in Finder, select it and choose Put Back."
        case .protected(let url): "\(url.path) is a protected location, so macobar won't change it. Undo it in Finder if it's really wanted."
        }
    }
}
