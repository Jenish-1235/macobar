import Foundation

extension UndoStep {
    /// Start of the line in `manage_file`'s trash result that says where the item now sits in the Trash.
    static let trashLocationPrefix = "Trash location: "

    /// The step that reverses a successful call to `toolName` with `input`, read from its arguments and `output`; nil when macobar can't undo it.
    static func inferred(toolName: String, input: ToolInput, output: String) -> UndoStep? {
        guard toolName == "manage_file", let path = input.string("path") else { return nil }
        let item = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        switch input.string("action") {
        case "create_folder": return .createdFolder(path: item)
        case "write_text": return input.bool("overwrite") ? nil : .wroteFile(path: item)
        case "move": return resultPath(in: output, after: "Moved to ", options: .anchored).map { .moved(from: item, to: $0) }
        case "copy": return resultPath(in: output, after: "Copied to ", options: .anchored).map { .copied(to: $0) }
        case "trash": return resultPath(in: output, after: "\n" + trashLocationPrefix, options: .backwards).map { .trashed(original: item, trashURL: $0) }
        default: return nil
        }
    }

    /// The path between `marker` (found with `options`) and the full stop ending `output`; reads to the end, since paths may hold line breaks.
    private static func resultPath(in output: String, after marker: String, options: String.CompareOptions) -> URL? {
        guard let start = output.range(of: marker, options: options)?.upperBound, output.hasSuffix(".") else { return nil }
        let path = output[start...].dropLast()
        return path.isEmpty ? nil : URL(fileURLWithPath: String(path))
    }
}
