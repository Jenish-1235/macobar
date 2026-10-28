import CoreGraphics

/// Where a mouse tool acts: a mark from the latest look, or a point the model gives.
enum PointReference: Equatable {
    /// A mark number from look_at_screen.
    case mark(Int)
    /// A point in global screen points with a top-left origin on the main screen.
    case point(CGPoint)

    /// Schema properties for a place given as `<prefix>mark`, or `<prefix>x` and `<prefix>y`; `place` says what it is for.
    static func parameters(prefix: String = "", place: String) -> [String: JSONValue] {
        [
            "\(prefix)mark": Schema.integer("Mark number from look_at_screen for \(place). Prefer this over x and y."),
            "\(prefix)x": Schema.number("Instead of a mark: \(place)'s x in screen points from the left of the main display."),
            "\(prefix)y": Schema.number("Instead of a mark: \(place)'s y in screen points from the top of the main display."),
        ]
    }

    /// The place in `input` under `prefix`, or nil when none is given; throws when it is ambiguous or half a point.
    static func optional(in input: ToolInput, prefix: String = "") throws -> PointReference? {
        let mark = input.integer("\(prefix)mark")
        let x = input.number("\(prefix)x")
        let y = input.number("\(prefix)y")
        switch (mark, x, y) {
        case (nil, nil, nil):
            return nil
        case (let mark?, nil, nil):
            guard mark >= 1 else { throw ToolError("Mark numbers start at 1. Use a number from look_at_screen.") }
            return .mark(mark)
        case (nil, let x?, let y?):
            return .point(CGPoint(x: x, y: y))
        case (nil, _, _):
            throw ToolError("Pass both \(prefix)x and \(prefix)y, or \(prefix)mark instead.")
        default:
            throw ToolError("Pass either \(prefix)mark or \(prefix)x and \(prefix)y, not both.")
        }
    }

    /// The place in `input` under `prefix`; throws when none is given.
    static func required(in input: ToolInput, prefix: String = "") throws -> PointReference {
        guard let reference = try optional(in: input, prefix: prefix) else {
            throw ToolError("Pass \(prefix)mark (a number from look_at_screen), or \(prefix)x and \(prefix)y in screen points.")
        }
        return reference
    }

    /// The screen point to act on and the mark it came from, if any, using marks in `store` as of `now`.
    func resolve(in store: ScreenMarkStore, at now: ContinuousClock.Instant = .now) throws -> (point: CGPoint, mark: ScreenMark?) {
        switch self {
        case .mark(let number):
            let mark = try store.mark(number, at: now)
            return (mark.center, mark)
        case .point(let point):
            return (point, nil)
        }
    }

    /// How activity lines name the place: the mark's label, "mark 12", or "point (640, 400)".
    func name(in store: ScreenMarkStore) -> String {
        switch self {
        case .mark(let number): (try? store.mark(number))?.name ?? "mark \(number)"
        case .point(let point): "point (\(Int(point.x)), \(Int(point.y)))"
        }
    }
}
