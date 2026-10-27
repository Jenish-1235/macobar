import CoreGraphics

/// One Dock item, reduced to what layout needs.
struct DockItem: Equatable, Sendable {
    /// Whether the item is an empty spacer tile.
    let isSpacer: Bool
    /// Item frame in AppKit screen coordinates (bottom-left origin).
    let frame: CGRect
}

/// Where the Dock and the chat bar's gap currently sit on screen.
struct DockGeometry: Equatable, Sendable {
    /// The Dock's frame in AppKit screen coordinates.
    let dockFrame: CGRect
    /// The spacer run right after Finder that the chat bar sits in.
    let gapFrame: CGRect

    /// Finds the gap in the items, or returns nil when no spacer follows the first item (Finder).
    init?(dockFrame: CGRect, items: [DockItem]) {
        let gapSpacers = items.dropFirst().prefix { $0.isSpacer }
        guard let first = gapSpacers.first, let last = gapSpacers.last else { return nil }
        self.dockFrame = dockFrame
        self.gapFrame = first.frame.union(last.frame)
    }
}

extension CGRect {
    /// Converts a top-left-origin Accessibility rect into AppKit's bottom-left-origin screen space.
    func flippedVertically(withinHeight height: CGFloat) -> CGRect {
        CGRect(x: minX, y: height - maxY, width: width, height: self.height)
    }
}
