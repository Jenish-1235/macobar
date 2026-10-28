# Dock
Keeps an empty gap in the real macOS Dock and reports where it is on screen.

## Files
- `DockGapReserver.swift`: adds or removes spacer tiles right after Finder via the Dock's preferences, then restarts the Dock. Remembers that the user added macobar so the gap can be restored on launch.
- `DockTiles.swift`: pure edits to the `persistent-apps` tile list (tested).
- `DockReader.swift`: reads the Dock's items through Accessibility and builds a `DockGeometry`.
- `DockObserver.swift`: polls the reader (10×/s at rest, 60×/s for a second after any change) and streams changes.
- `DockGeometry.swift`: the Dock frame and gap frame, plus the gap-finding rule (tested).
- `DockProcess.swift`: finds and restarts the Dock process.

## Public surface
- `DockGapReserver.isGapReserved`, `wasAddedByUser`, `reserveGap(width:)` / `releaseGap()`
- `DockObserver.geometryUpdates() -> AsyncStream<DockGeometry?>` (nil while the Dock or gap isn't visible)

## Depends on
Accessibility permission (granted via Permissions).

## Gotchas
- The Dock strips custom keys from tiles, so the gap is identified by position: the spacer run right after Finder. A user's own spacers in that spot are treated as the gap.
- Accessibility frames use a top-left origin on the primary screen; they're flipped to AppKit's bottom-left origin in `DockReader`.
- The gap only exists while macobar runs: it's removed on every quit and restored on launch, each costing one Dock restart. The preferences are re-read before every change. At launch macobar waits until the Dock has been running for 2 seconds (`DockProcess.waitUntilSettled()`), then checks the gap again after the restart, retrying up to 3 times, because a Dock still starting up can save its old layout over it.
- `releaseGap()` does nothing unless the user added macobar, so a user's own spacers after Finder are safe.
- A force quit (SIGKILL) or crash can't clean up; the gap stays until macobar's next launch and quit.
- Only a bottom Dock without magnification is handled so far.
