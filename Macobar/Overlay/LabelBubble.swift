import SwiftUI

/// Short text in an accent bubble sitting just above a point, kept inside the screen; Macie's face leads it, so a label never passes for the system's or an app's own text.
struct LabelBubble: View {
    /// What the bubble says.
    let text: String
    /// The point the bubble sits above, in view coordinates.
    let anchor: CGPoint
    /// Size of the screen's canvas, to keep the bubble on it.
    let canvasSize: CGSize
    /// How far the bubble has drawn in, from 0 to 1.
    let progress: CGFloat
    /// The bubble's measured size, used to place it.
    @State private var size = CGSize.zero

    var body: some View {
        HStack(spacing: 6) {
            Macie(mood: .resting, size: OverlayStyle.labelMacieSize, showsGround: false)
                .compositingGroup() // Her eyes show the bubble, not a hole through it.
            Text(text)
                .font(OverlayStyle.labelFont)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(OverlayStyle.ink))
        .overlay(Capsule().strokeBorder(OverlayStyle.outline, lineWidth: OverlayStyle.outlineWidth))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
        .frame(width: OverlayStyle.labelMaxWidth) // Wraps longer text but leaves the bubble hugging shorter text.
        .scaleEffect(0.85 + 0.15 * progress, anchor: .bottom)
        .opacity(progress)
        .position(center)
    }

    /// The bubble's centre: above the anchor, clamped so the whole bubble stays on screen.
    private var center: CGPoint {
        let x = min(max(anchor.x, size.width / 2), canvasSize.width - size.width / 2)
        let y = min(max(anchor.y - OverlayStyle.labelLift - size.height / 2, size.height / 2), canvasSize.height - size.height / 2)
        return CGPoint(x: x, y: y)
    }
}
