import Foundation

/// A checked request to draw: the shapes, as given, and how long they stay up.
struct DrawingRequest {
    /// Most shapes one request may draw.
    static let shapeLimit = 20
    /// Most points one freehand path may have.
    static let pointLimit = 500
    /// Longest label text, in characters.
    static let textLimit = 80
    /// Seconds a drawing stays up when no duration is given.
    static let defaultSeconds = 6.0
    /// Longest a drawing may stay up, in seconds.
    static let longestSeconds = 60.0

    /// The shapes, in the coordinates they were given in.
    let shapes: [OverlayShape]
    /// How long the shapes stay before fading out.
    let duration: Duration

    /// Reads `shapes` and `duration` from a tool call's arguments, or explains what to fix.
    init(arguments: [String: JSONValue]) throws {
        let list = try Self.shapeList(arguments["shapes"])
        guard !list.isEmpty else { throw DrawingRequestError("Pass at least one shape in \"shapes\".") }
        guard list.count <= Self.shapeLimit else {
            throw DrawingRequestError("Draw at most \(Self.shapeLimit) shapes at once; \(list.count) were given.")
        }
        shapes = try list.enumerated().map { index, value in
            do {
                return try Self.shape(value)
            } catch let error as DrawingRequestError {
                throw DrawingRequestError("Shape \(index + 1): \(error.message)")
            }
        }
        let seconds = arguments["duration"]?.number ?? Self.defaultSeconds
        guard seconds > 0, seconds <= Self.longestSeconds else {
            throw DrawingRequestError("duration must be more than 0 and at most \(Int(Self.longestSeconds)) seconds.")
        }
        duration = .milliseconds(Int((seconds * 1000).rounded()))
    }

    /// The array of shapes, also accepted as a JSON string since some models send arrays that way.
    private static func shapeList(_ value: JSONValue?) throws -> [JSONValue] {
        if let array = value?.array { return array }
        if let text = value?.string, let array = (try? JSONValue.parse(text))?.array { return array }
        throw DrawingRequestError("\"shapes\" must be an array of shape objects, e.g. [{\"kind\": \"pointer\", \"point\": {\"x\": 200, \"y\": 300}}].")
    }

    /// One shape object, checked for the fields its kind needs.
    private static func shape(_ value: JSONValue) throws -> OverlayShape {
        guard let kindName = value["kind"]?.string else {
            throw DrawingRequestError("missing \"kind\". Use one of: \(kindNames).")
        }
        guard let kind = OverlayShape.Kind(rawValue: kindName) else {
            throw DrawingRequestError("unknown kind \"\(kindName)\". Use one of: \(kindNames).")
        }
        switch kind {
        case .highlight: return .highlight(try rect(value["rect"]))
        case .circle: return .circle(try rect(value["rect"]))
        case .arrow: return .arrow(from: try point(value["from"], named: "from"), to: try point(value["to"], named: "to"))
        case .label: return .label(try text(value["text"]), at: try point(value["point"], named: "point"))
        case .path: return .path(try points(value["points"]))
        case .spotlight: return .spotlight(try rect(value["rect"]))
        case .pointer: return .pointer(try point(value["point"], named: "point"))
        }
    }

    /// Every kind name, for error messages.
    private static var kindNames: String {
        OverlayShape.Kind.allCases.map(\.rawValue).joined(separator: ", ")
    }

    /// A `{"x", "y"}` object as a point.
    private static func point(_ value: JSONValue?, named name: String) throws -> CGPoint {
        guard let x = value?["x"]?.number, let y = value?["y"]?.number else {
            throw DrawingRequestError("\"\(name)\" must be an object like {\"x\": 200, \"y\": 300}.")
        }
        return CGPoint(x: x, y: y)
    }

    /// A `{"x", "y", "width", "height"}` object with a positive size as a rect.
    private static func rect(_ value: JSONValue?) throws -> CGRect {
        guard let x = value?["x"]?.number, let y = value?["y"]?.number,
              let width = value?["width"]?.number, let height = value?["height"]?.number
        else { throw DrawingRequestError("\"rect\" must be an object like {\"x\": 100, \"y\": 80, \"width\": 240, \"height\": 40}.") }
        guard width > 0, height > 0 else { throw DrawingRequestError("\"rect\" needs a width and height above 0.") }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The label's text, trimmed, non-empty and short.
    private static func text(_ value: JSONValue?) throws -> String {
        guard let text = value?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw DrawingRequestError("a label needs \"text\".")
        }
        guard text.count <= textLimit else { throw DrawingRequestError("keep label text to \(textLimit) characters.") }
        return text
    }

    /// The freehand path's points: at least two, at most `pointLimit`.
    private static func points(_ value: JSONValue?) throws -> [CGPoint] {
        guard let list = value?.array, list.count >= 2 else {
            throw DrawingRequestError("a path needs \"points\": at least two objects like {\"x\": 200, \"y\": 300}.")
        }
        guard list.count <= pointLimit else { throw DrawingRequestError("a path may have at most \(pointLimit) points.") }
        return try list.map { try point($0, named: "points") }
    }
}

/// Why a drawing request can't be drawn, in words the model can act on.
struct DrawingRequestError: LocalizedError {
    /// What to fix.
    let message: String

    /// Creates an error with `message`.
    init(_ message: String) {
        self.message = message
    }

    /// The message, for `localizedDescription`.
    var errorDescription: String? { message }
}
