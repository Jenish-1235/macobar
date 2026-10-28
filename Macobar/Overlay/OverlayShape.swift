import CoreGraphics

/// One mark Macie draws on the screen; its coordinates are in whichever space the holder is working in.
enum OverlayShape: Equatable, Sendable {
    /// A glowing rounded rectangle around a rect.
    case highlight(CGRect)
    /// An ellipse ring inside a rect.
    case circle(CGRect)
    /// A slightly curved arrow with its head at `to`.
    case arrow(from: CGPoint, to: CGPoint)
    /// Short text in a bubble just above a point.
    case label(String, at: CGPoint)
    /// A freehand line through the points, in order.
    case path([CGPoint])
    /// Dims everything except a rect.
    case spotlight(CGRect)
    /// Macie's cursor dot, which travels to a point and pulses there.
    case pointer(CGPoint)

    /// The shape kinds by the names the model uses.
    enum Kind: String, CaseIterable, Sendable {
        /// `highlight`, which needs a rect.
        case highlight
        /// `circle`, which needs a rect.
        case circle
        /// `arrow`, which needs from and to.
        case arrow
        /// `label`, which needs a point and text.
        case label
        /// `path`, which needs points.
        case path
        /// `spotlight`, which needs a rect.
        case spotlight
        /// `pointer`, which needs a point.
        case pointer
    }

    /// The same shape with every point passed through `transform`, e.g. into another coordinate space.
    func mapped(_ transform: (CGPoint) -> CGPoint) -> OverlayShape {
        switch self {
        case .highlight(let rect): .highlight(Self.map(rect, transform))
        case .circle(let rect): .circle(Self.map(rect, transform))
        case .arrow(let from, let to): .arrow(from: transform(from), to: transform(to))
        case .label(let text, let point): .label(text, at: transform(point))
        case .path(let points): .path(points.map(transform))
        case .spotlight(let rect): .spotlight(Self.map(rect, transform))
        case .pointer(let point): .pointer(transform(point))
        }
    }

    /// `rect` with both corners passed through `transform`, kept upright when the transform flips an axis.
    private static func map(_ rect: CGRect, _ transform: (CGPoint) -> CGPoint) -> CGRect {
        let first = transform(CGPoint(x: rect.minX, y: rect.minY))
        let second = transform(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: min(first.x, second.x), y: min(first.y, second.y), width: abs(second.x - first.x), height: abs(second.y - first.y))
    }
}
