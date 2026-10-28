import SwiftUI

/// The outlines behind arrows, freehand paths and spotlights, in view coordinates.
enum OverlayPaths {
    /// A quadratic curve from `start` to `end`, bowed to one side, with an open arrowhead at `end`.
    static func arrow(from start: CGPoint, to end: CGPoint) -> Path {
        let length = hypot(end.x - start.x, end.y - start.y)
        let normal = length > 0 ? CGPoint(x: -(end.y - start.y) / length, y: (end.x - start.x) / length) : .zero
        let bend = length * OverlayStyle.arrowBend
        let control = CGPoint(x: (start.x + end.x) / 2 + normal.x * bend, y: (start.y + end.y) / 2 + normal.y * bend)
        let heading = atan2(end.y - control.y, end.x - control.x)
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        path.move(to: headCorner(of: end, heading: heading + .pi * 5 / 6))
        path.addLine(to: end)
        path.addLine(to: headCorner(of: end, heading: heading - .pi * 5 / 6))
        return path
    }

    /// A line through `points`, in order.
    static func polyline(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        return path
    }

    /// A rounded ring just outside `rect`.
    static func ring(around rect: CGRect) -> Path {
        let padding = OverlayStyle.ringPadding
        return Path(roundedRect: rect.insetBy(dx: -padding, dy: -padding), cornerRadius: OverlayStyle.ringCornerRadius, style: .continuous)
    }

    /// The whole of `bounds` with a rounded hole around `rect`, for an even-odd fill.
    static func spotlight(around rect: CGRect, in bounds: CGRect) -> Path {
        var path = Path(bounds)
        path.addPath(ring(around: rect))
        return path
    }

    /// One back corner of an arrowhead whose tip is at `tip`, along `heading`.
    private static func headCorner(of tip: CGPoint, heading: CGFloat) -> CGPoint {
        CGPoint(x: tip.x + cos(heading) * OverlayStyle.arrowheadLength, y: tip.y + sin(heading) * OverlayStyle.arrowheadLength)
    }
}
