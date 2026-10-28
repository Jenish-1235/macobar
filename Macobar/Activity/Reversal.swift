import Foundation

/// The file change that reverses an `UndoStep`.
enum Reversal: Equatable, Sendable {
    /// Move the item at `from` back to `to`.
    case move(from: URL, to: URL)
    /// Move the item out of the Trash at `from` back to `to`.
    case putBack(from: URL, to: URL)
    /// Move the item to the Trash.
    case trash(URL)
    /// Move the folder to the Trash, only while it's still empty.
    case trashEmptyFolder(URL)

    /// Every item the reversal moves or trashes, and where it moves them.
    var items: [URL] {
        switch self {
        case .move(let source, let destination), .putBack(let source, let destination): [source, destination]
        case .trash(let item), .trashEmptyFolder(let item): [item]
        }
    }
}
