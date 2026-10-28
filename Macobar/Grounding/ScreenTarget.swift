import CoreGraphics

/// Something on screen worth a mark: what it is, what it says, and where it is.
struct ScreenTarget: Equatable, Sendable {
    /// Where a target was found.
    enum Source: Sendable {
        /// The front window's Accessibility elements.
        case accessibility
        /// Text recognized in the screenshot.
        case textRecognition
    }

    /// Longest label kept, in characters.
    static let labelLimit = 60

    /// What it is.
    let kind: MarkKind
    /// What it says on one line, at most `labelLimit` characters; empty for an unlabelled control.
    let label: String
    /// Where it is, in global screen points with a top-left origin on the main screen.
    let frame: CGRect
    /// Where it was found.
    let source: Source

    /// A target whose `label` is flattened to one trimmed line and shortened to `labelLimit` characters.
    init(kind: MarkKind, label: String, frame: CGRect, source: Source) {
        let line = label.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        self.kind = kind
        self.label = line.count <= Self.labelLimit ? line : String(line.prefix(Self.labelLimit - 1)) + "…"
        self.frame = frame
        self.source = source
    }
}
