import CoreFoundation
import CoreGraphics
import Foundation

/// Keeps a run of spacer tiles right after Finder for the chat bar while macobar runs.
struct DockGapReserver {
    /// Preferences domain the Dock reads its layout from.
    private static let dockDomain = DockProcess.bundleIdentifier
    /// Key holding the user's pinned app tiles.
    private static let tilesKey = "persistent-apps"
    /// Key holding the Dock icon size.
    private static let tileSizeKey = "tilesize"
    /// Icon size macOS uses when the user never changed it.
    private static let defaultTileSize: CGFloat = 48
    /// macobar's own preference recording that the user added it to the Dock.
    private static let wasAddedKey = "addedToDock"

    /// Whether the Dock already has the gap.
    var isGapReserved: Bool {
        DockTiles.leadingSpacerCount(in: currentTiles() ?? []) > 0
    }

    /// Whether the user has added macobar to the Dock, so the gap is restored on every launch.
    var wasAddedByUser: Bool {
        UserDefaults.standard.bool(forKey: Self.wasAddedKey)
    }

    /// Makes the gap wide enough for `width` points and remembers that the user wants it.
    func reserveGap(width: CGFloat) {
        UserDefaults.standard.set(true, forKey: Self.wasAddedKey)
        setLeadingSpacers(count: Int((width / tileSize()).rounded(.up)))
    }

    /// Removes the gap, returning the Dock to how the user had it; never touches spacers macobar didn't add.
    func releaseGap() {
        guard wasAddedByUser else { return }
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

    /// The user's pinned tiles as the Dock last saved them, or nil if its preferences can't be read.
    private func currentTiles() -> [DockTiles.Tile]? {
        CFPreferencesAppSynchronize(Self.dockDomain as CFString)
        return CFPreferencesCopyAppValue(Self.tilesKey as CFString, Self.dockDomain as CFString) as? [DockTiles.Tile]
    }

    /// The user's Dock icon size in points.
    private func tileSize() -> CGFloat {
        let size = CFPreferencesCopyAppValue(Self.tileSizeKey as CFString, Self.dockDomain as CFString) as? Double
        return size.map { CGFloat($0) } ?? Self.defaultTileSize
    }
}
