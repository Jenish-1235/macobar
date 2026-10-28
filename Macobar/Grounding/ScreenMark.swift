import CoreGraphics

/// A target with a number drawn on it, which the model uses to refer to it.
struct ScreenMark: Equatable, Sendable {
    /// The number on its badge, from 1.
    let number: Int
    /// What it is and where.
    let target: ScreenTarget

    /// The middle of the target, where clicks land.
    var center: CGPoint {
        CGPoint(x: target.frame.midX, y: target.frame.midY)
    }

    /// How activity lines and results name it: its quoted label, or "mark 12" when it has none.
    var name: String {
        target.label.isEmpty ? "mark \(number)" : "'\(target.label)'"
    }

    /// Its line in the list sent to the model, e.g. "12 button 'Export' at (840,112,64,22)".
    var summary: String {
        let frame = target.frame.integral
        let label = target.label.isEmpty ? "" : " '\(target.label)'"
        return "\(number) \(target.kind.rawValue)\(label) at (\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height)))"
    }
}
