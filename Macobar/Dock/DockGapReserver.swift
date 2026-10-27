import CoreFoundation
import CoreGraphics

/// Keeps a run of spacer tiles right after Finder for the chat bar, and removes it on quit.
struct DockGapReserver {
    /// Preferences domain the Dock reads its layout from.
    private static let dockDomain = DockProcess.bundleIdentifier
    /// Key holding the user's pinned app tiles.
    private static let tilesKey = "persistent-apps"
    /// Key holding the Dock icon size.
    private static let tileSizeKey = "tilesize"
    /// Icon size macOS uses when the user never changed it.
    private static let defaultTileSize: CGFloat = 48

    /// Whether the Dock already has the gap.
    var isGapReserved: Bool {
        DockTiles.leadingSpacerCount(in: currentTiles() ?? []) > 0
    }

    /// Makes the gap wide enough for `width` points.
    func reserveGap(width: CGFloat) {
        setLeadingSpacers(count: Int((width / tileSize()).rounded(.up)))
    }

    /// Removes the gap, returning the Dock to how the user had it.
    func releaseGap() {
        setLeadingSpacers(count: 0)
    }

    /// Writes exactly `count` leading spacers, restarting the Dock only when something changed.
    private func setLeadingSpacers(count: Int) {
        // Never write when the read fails, or the user's pinned apps would be wiped.
        guard let tiles = currentTiles(), DockTiles.leadingSpacerCount(in: tiles) != count else { return }
        let updatedTiles = DockTiles.replacingLeadingSpacers(in: tiles, with: count)
        CFPreferencesSetAppValue(Self.tilesKey as CFString, updatedTiles as CFArray, Self.dockDomain as CFString)
        CFPreferencesAppSynchronize(Self.dockDomain as CFString)
        DockProcess.restart()
    }

    /// The user's pinned tiles, or nil if the Dock's preferences can't be read.
    private func currentTiles() -> [DockTiles.Tile]? {
        CFPreferencesCopyAppValue(Self.tilesKey as CFString, Self.dockDomain as CFString) as? [DockTiles.Tile]
    }

    /// The user's Dock icon size in points.
    private func tileSize() -> CGFloat {
        let size = CFPreferencesCopyAppValue(Self.tileSizeKey as CFString, Self.dockDomain as CFString) as? Double
        return size.map { CGFloat($0) } ?? Self.defaultTileSize
    }
}
