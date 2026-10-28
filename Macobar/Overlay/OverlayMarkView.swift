import SwiftUI

/// One shape on one screen, drawing itself in when it appears.
struct OverlayMarkView: View {
    /// The shape, in this screen's view coordinates.
    let shape: OverlayShape
    /// Size of the screen's canvas.
    let canvasSize: CGSize
    /// Seconds to wait before drawing in, so marks appear in order.
    let delay: Double
    /// Users who prefer reduced motion get a plain cross-fade.
    @Environment(\.accessibilityReduceMotion) private var prefersReducedMotion
    /// How far the mark has drawn in, from 0 to 1.
    @State private var progress: CGFloat = 0

    var body: some View {
        mark.onAppear {
            if prefersReducedMotion {
                progress = 1
            } else {
                withAnimation(OverlayStyle.drawIn.delay(delay)) { progress = 1 }
            }
        }
    }

    /// The mark for the shape's kind.
    @ViewBuilder private var mark: some View {
        switch shape {
        case .highlight(let rect):
            ZStack {
                OverlayPaths.ring(around: rect).fill(OverlayStyle.ink.opacity(OverlayStyle.highlightTint))
                stroke(OverlayPaths.ring(around: rect), drawnTo: 1)
            }
            .scaleEffect(1.08 - 0.08 * progress, anchor: unitPoint(rect.midX, rect.midY))
            .opacity(progress)
        case .circle(let rect):
            stroke(Ellipse().path(in: rect), drawnTo: progress)
        case .arrow(let from, let to):
            stroke(OverlayPaths.arrow(from: from, to: to), drawnTo: progress)
        case .label(let text, let point):
            LabelBubble(text: text, anchor: point, canvasSize: canvasSize, progress: progress)
        case .path(let points):
            stroke(OverlayPaths.polyline(points), drawnTo: progress)
        case .spotlight(let rect):
            OverlayPaths.spotlight(around: rect, in: CGRect(origin: .zero, size: canvasSize))
                .fill(OverlayStyle.dim, style: FillStyle(eoFill: true))
                .opacity(progress)
        case .pointer(let point) where CGRect(origin: .zero, size: canvasSize).contains(point):
            PointerDot(target: point, start: CGPoint(x: canvasSize.width / 2, y: canvasSize.height), delay: delay)
        case .pointer:
            EmptyView()
        }
    }

    /// `path` stroked in the accent colour over a soft white edge, with a glow, drawn from its start up to `end`.
    private func stroke(_ path: Path, drawnTo end: CGFloat) -> some View {
        let trimmed = path.trim(from: 0, to: end)
        return ZStack {
            trimmed.stroke(OverlayStyle.outline, style: lineStyle(width: OverlayStyle.lineWidth + 2 * OverlayStyle.outlineWidth))
            trimmed.stroke(OverlayStyle.ink, style: lineStyle(width: OverlayStyle.lineWidth))
        }
        .shadow(color: OverlayStyle.ink.opacity(0.5), radius: OverlayStyle.glowRadius)
    }

    /// A rounded stroke of `width`.
    private func lineStyle(width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    /// The canvas point (`x`, `y`) as a fraction of its size, for scaling about it.
    private func unitPoint(_ x: CGFloat, _ y: CGFloat) -> UnitPoint {
        UnitPoint(x: x / max(canvasSize.width, 1), y: y / max(canvasSize.height, 1))
    }
}
