import AppKit
import SwiftUI

/// Colours, sizes and motion for Macie's screen drawings.
enum OverlayStyle {
    /// Ink for every mark: the user's accent colour.
    static let ink = Color(nsColor: .controlAccentColor)
    /// The soft white edge that keeps marks readable on any background.
    static let outline = Color.white.opacity(0.85)
    /// Dimming outside a spotlight.
    static let dim = Color.black.opacity(0.45)

    /// Width of strokes.
    static let lineWidth: CGFloat = 4
    /// Extra width of the white edge under a stroke, on each side.
    static let outlineWidth: CGFloat = 1.5
    /// Blur radius of the glow around strokes.
    static let glowRadius: CGFloat = 8
    /// Space between a highlighted or spotlit rect and its ring.
    static let ringPadding: CGFloat = 6
    /// Corner radius of highlight rings and spotlight holes.
    static let ringCornerRadius: CGFloat = 10
    /// Opacity of the tint inside a highlight.
    static let highlightTint = 0.12
    /// How far an arrow bows out, as a fraction of its length.
    static let arrowBend: CGFloat = 0.12
    /// Length of each side of an arrowhead.
    static let arrowheadLength: CGFloat = 16

    /// Label text.
    static let labelFont = Font.system(size: 13, weight: .semibold)
    /// Width of Macie at the start of every label, marking it as hers.
    static let labelMacieSize: CGFloat = 12
    /// Widest a label bubble gets; longer text wraps.
    static let labelMaxWidth: CGFloat = 280
    /// Gap between a label and the point it sits above.
    static let labelLift: CGFloat = 10
    /// Diameter of Macie's pointer dot.
    static let pointerSize: CGFloat = 16
    /// How far the pointer's pulse ring grows.
    static let pulseScale: CGFloat = 2.8

    /// Motion for a mark drawing in.
    static let drawIn = Animation.spring(response: 0.35, dampingFraction: 0.82)
    /// Delay between marks drawn together, so they appear in order.
    static let stagger = 0.08
    /// Motion for whole drawings fading in and out.
    static let fade = Animation.easeInOut(duration: 0.35)
    /// Motion for the pointer travelling to its point.
    static let travel = Animation.spring(response: 0.6, dampingFraction: 0.78)
    /// Motion for the pointer's repeating pulse.
    static let pulse = Animation.easeOut(duration: 1.2).repeatForever(autoreverses: false)
}
