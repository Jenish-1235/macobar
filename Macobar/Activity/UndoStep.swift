import Foundation

/// A file change Macie made that macobar can reverse on its own.
enum UndoStep: Codable, Sendable, Equatable {
    /// An item moved or renamed from `from` to `to`.
    case moved(from: URL, to: URL)
    /// A new copy made at `to`.
    case copied(to: URL)
    /// A new file written at `path`.
    case wroteFile(path: URL)
    /// A folder created at `path`.
    case createdFolder(path: URL)
    /// An item moved from `original` to the Trash, where it now sits at `trashURL`.
    case trashed(original: URL, trashURL: URL)

    /// The file change that reverses this step.
    var reversal: Reversal {
        switch self {
        case .moved(let original, let current): .move(from: current, to: original)
        case .copied(let copy): .trash(copy)
        case .wroteFile(let file): .trash(file)
        case .createdFolder(let folder): .trashEmptyFolder(folder)
        case .trashed(let original, let trashURL): .putBack(from: trashURL, to: original)
        }
    }
}
