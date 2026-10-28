import Foundation
import Observation

/// What every screen's canvas is showing right now.
@MainActor
@Observable
final class OverlayBoard {
    /// The drawing on screen, or nil when nothing is drawn.
    var drawing: OverlayDrawing?
}

/// Shapes drawn together, which appear and fade out as one.
struct OverlayDrawing {
    /// Tells this drawing from the one it replaces, so the old fades out as the new draws in.
    let id = UUID()
    /// The shapes, in AppKit global screen coordinates (bottom-left origin).
    let shapes: [OverlayShape]
}
