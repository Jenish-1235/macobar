import Testing

/// Verifies edits to the Dock's pinned-tile list.
struct DockTilesTests {
    /// A pinned app tile with the given label.
    private func app(_ label: String) -> DockTiles.Tile {
        ["tile-type": "file-tile", "tile-data": ["file-label": label]]
    }

    /// The labels of app tiles in order, with spacers shown as "_".
    private func labels(_ tiles: [DockTiles.Tile]) -> [String] {
        tiles.map { ($0["tile-data"] as? [String: Any])?["file-label"] as? String ?? "" }.map { $0.isEmpty ? "_" : $0 }
    }

    @Test("Adds spacers in front of pinned apps")
    func addsLeadingSpacers() {
        let tiles = DockTiles.replacingLeadingSpacers(in: [app("Mail")], with: 2)
        #expect(labels(tiles) == ["_", "_", "Mail"])
        #expect(DockTiles.leadingSpacerCount(in: tiles) == 2)
    }

    @Test("Resizes an existing gap without duplicating it")
    func resizesExistingGap() {
        let tiles = DockTiles.replacingLeadingSpacers(in: [DockTiles.spacer, DockTiles.spacer, DockTiles.spacer, app("Mail")], with: 1)
        #expect(labels(tiles) == ["_", "Mail"])
    }

    @Test("Releasing the gap keeps the user's own spacers between apps")
    func releaseKeepsLaterSpacers() {
        let tiles = DockTiles.replacingLeadingSpacers(in: [DockTiles.spacer, app("Mail"), DockTiles.spacer, app("Notes")], with: 0)
        #expect(labels(tiles) == ["Mail", "_", "Notes"])
    }
}
