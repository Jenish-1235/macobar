/// Pure edits to the Dock's `persistent-apps` tile list.
enum DockTiles {
    /// One tile entry, exactly as the Dock stores it.
    typealias Tile = [String: Any]

    /// The entry the Dock itself writes for an empty spacer.
    static var spacer: Tile { ["tile-type": "spacer-tile", "tile-data": ["file-label": ""]] }

    /// Counts the spacer tiles at the very start of the list.
    static func leadingSpacerCount(in tiles: [Tile]) -> Int {
        tiles.prefix(while: isSpacer).count
    }

    /// Returns the list with its leading spacers replaced by exactly `count` spacers.
    static func replacingLeadingSpacers(in tiles: [Tile], with count: Int) -> [Tile] {
        Array(repeating: spacer, count: count) + tiles.drop(while: isSpacer)
    }

    /// Whether a tile is a spacer.
    private static func isSpacer(_ tile: Tile) -> Bool {
        tile["tile-type"] as? String == "spacer-tile"
    }
}
