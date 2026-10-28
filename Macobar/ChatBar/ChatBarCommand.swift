/// An item in the field's right-click menu.
enum ChatBarCommand: CaseIterable {
    /// Pick a different model.
    case changeModel
    /// Manage the MCP servers Macie uses.
    case connections
    /// Let other AI apps use Macie's tools.
    case shareTools
    /// See what Macie did, and undo file changes.
    case history
    /// Remove the gap and quit.
    case quit

    /// The menu item's title.
    var title: String {
        switch self {
        case .changeModel: "Change Model…"
        case .connections: "Connections…"
        case .shareTools: "Share Tools with AI Apps…"
        case .history: "History…"
        case .quit: "Quit macobar"
        }
    }
}
