import AppKit
import ApplicationServices

/// Draws temporary, animated marks over the screen to point things out.
struct DrawOnScreenTool: Tool {
    /// Where the marks are drawn.
    private let overlay: ScreenOverlay

    /// Name the model calls it by.
    let name = "draw_on_screen"
    /// When to call it and what it returns.
    let description = """
        Draws temporary animated marks over the screen to show the user where something is or guide them; for an app \
        control use point_at_element instead. Coordinates are screen points from the main screen's top-left, not \
        screenshot pixels (scale those by the screen size this returns). Each call replaces the last drawing.
        """

    /// Creates the tool, drawing on `overlay`.
    init(overlay: ScreenOverlay) {
        self.overlay = overlay
    }

    /// Takes the shapes and an optional duration.
    var parameters: JSONValue {
        let point = Schema.object(["x": Schema.number("From the left."), "y": Schema.number("From the top.")], required: ["x", "y"])
        let shape = Schema.object([
            "kind": Schema.oneOf(OverlayShape.Kind.allCases.map(\.rawValue), "What to draw."),
            "rect": Schema.object([
                "x": Schema.number("Left edge."),
                "y": Schema.number("Top edge."),
                "width": Schema.number("Width."),
                "height": Schema.number("Height."),
            ], required: ["x", "y", "width", "height"]),
            "from": point,
            "to": point,
            "point": point,
            "points": ["type": "array", "items": point, "description": .string("Path points, 2 to \(DrawingRequest.pointLimit).")],
            "text": Schema.string("Label text, at most \(DrawingRequest.textLimit) characters."),
        ], required: ["kind"])
        return Schema.object([
            "shapes": [
                "type": "array",
                "items": shape,
                "description": .string("""
                    Up to \(DrawingRequest.shapeLimit). highlight, circle, spotlight (dims all else) need rect; arrow \
                    needs from, to; label needs point, text; path needs points; pointer needs point.
                    """),
            ],
            "duration": Schema.number("Seconds shown, at most \(Int(DrawingRequest.longestSeconds)); default \(Int(DrawingRequest.defaultSeconds))."),
        ], required: ["shapes"])
    }

    /// Describes the drawing.
    func activity(for input: ToolInput) -> String { "Drawing on the screen" }

    /// Checks the shapes and draws them.
    func run(_ input: ToolInput) async throws -> String {
        let request = try DrawingRequest(arguments: input.arguments)
        let screen = try await show(request.shapes, on: overlay, for: request.duration)
        let count = request.shapes.count == 1 ? "1 shape" : "\(request.shapes.count) shapes"
        return "Drew \(count) for \(request.duration). The main screen is \(Int(screen.width)) × \(Int(screen.height)) points."
    }
}

/// Highlights a control found by `list_ui_elements`, labels it, and moves Macie's pointer to it.
struct PointAtElementTool: Tool {
    /// Where the marks are drawn.
    private let overlay: ScreenOverlay

    /// Name the model calls it by.
    let name = "point_at_element"
    /// When to call it and what it returns.
    let description = """
        Points out a control from list_ui_elements (highlight, label, your pointer) to show where to click or what \
        it is; use draw_on_screen for anything else. Returns its frame in top-left screen points.
        """

    /// Creates the tool, drawing on `overlay`.
    init(overlay: ScreenOverlay) {
        self.overlay = overlay
    }

    /// Takes an optional app, the element id and an optional label.
    var parameters: JSONValue {
        Schema.object([
            "app": Schema.string("The element's app; default frontmost."),
            "element_id": Schema.string("Id from list_ui_elements, e.g. \"0.3.1\"."),
            "label": Schema.string("Short text shown above it; default its name."),
        ], required: ["element_id"])
    }

    /// Names the label when given, else the app.
    func activity(for input: ToolInput) -> String {
        guard let label = input.string("label") else { return "Pointing at a control in \(input.string("app") ?? "the front app")" }
        return "Pointing at \"\(label)\""
    }

    /// Finds the element, reads its frame, and draws a highlight, label and pointer on it.
    func run(_ input: ToolInput) async throws -> String {
        let path = try input.requiredString("element_id")
        let element = try Self.element(at: path, in: appOtherThanMacobar(named: input.string("app")))
        guard let frame = Self.frame(of: element), frame.width > 0, frame.height > 0 else {
            throw ToolError("Element \(path) has no place on screen; it may be hidden. Call list_ui_elements again.")
        }
        var shapes: [OverlayShape] = [.highlight(frame)]
        if let text = input.string("label") ?? [element.title, element.label].compactMap(\.self).first(where: { !$0.isEmpty }) {
            shapes.append(.label(String(text.prefix(DrawingRequest.textLimit)), at: CGPoint(x: frame.midX, y: frame.minY)))
        }
        shapes.append(.pointer(CGPoint(x: frame.maxX, y: frame.maxY)))
        _ = try await show(shapes, on: overlay, for: .seconds(DrawingRequest.defaultSeconds))
        return "Pointing at \(element.role ?? "the element") at x \(Int(frame.minX)), y \(Int(frame.minY)), \(Int(frame.width)) × \(Int(frame.height)) points."
    }

    /// The element at `path` (child indices joined by dots) under `app`'s focused window.
    private static func element(at path: String, in app: NSRunningApplication) throws -> AccessibilityElement {
        var element = try AccessibilityElement.focusedWindow(of: app)
        for component in path.split(separator: ".") {
            let children = element.children
            guard let index = Int(component), children.indices.contains(index) else {
                throw ToolError("Element \(path) no longer exists. Call list_ui_elements again for fresh ids.")
            }
            element = children[index]
        }
        return element
    }

    /// The element's frame in Accessibility coordinates (top-left origin of the main screen).
    private static func frame(of element: AccessibilityElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let originValue = axValue(element.attribute(kAXPositionAttribute)), AXValueGetValue(originValue, .cgPoint, &origin),
              let sizeValue = axValue(element.attribute(kAXSizeAttribute)), AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// `object` as an AXValue, after checking its Core Foundation type.
    private static func axValue(_ object: CFTypeRef?) -> AXValue? {
        guard let object, CFGetTypeID(object) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(object, to: AXValue.self)
    }
}

/// Removes whatever Macie has drawn on the screen.
struct ClearScreenDrawingsTool: Tool {
    /// Where the marks are drawn.
    private let overlay: ScreenOverlay

    /// Name the model calls it by.
    let name = "clear_screen_drawings"
    /// When to call it and what it returns.
    let description = """
        Removes marks drawn by draw_on_screen or point_at_element. Call it when the user is done or they're in the way.
        """

    /// Creates the tool, clearing `overlay`.
    init(overlay: ScreenOverlay) {
        self.overlay = overlay
    }

    /// Takes no arguments.
    var parameters: JSONValue { Schema.object() }

    /// Describes the clearing.
    func activity(for input: ToolInput) -> String { "Clearing the screen drawings" }

    /// Fades the drawing out.
    func run(_ input: ToolInput) async throws -> String {
        await overlay.clear()
        return "Cleared the screen drawings."
    }
}

/// Points at a numbered mark from the latest look_at_screen: highlight, label and pointer.
struct PointAtMarkTool: Tool {
    /// Where the marks are drawn.
    private let overlay: ScreenOverlay
    /// The marks from the latest look_at_screen.
    private let marks: ScreenMarkStore

    /// Name the model calls it by.
    let name = "point_at_mark"
    /// When to call it and what it returns.
    let description = """
        Points out a numbered mark from your latest look_at_screen (highlight, label, your pointer), in any app \
        including web pages. Use it before wait_for_user; the frame it returns is wait_for_user's rect.
        """

    /// Creates the tool, drawing on `overlay` at marks from `marks`.
    init(overlay: ScreenOverlay, marks: ScreenMarkStore) {
        self.overlay = overlay
        self.marks = marks
    }

    /// Takes the mark number and an optional label.
    var parameters: JSONValue {
        Schema.object([
            "mark": Schema.integer("Mark number from look_at_screen."),
            "label": Schema.string("Short text shown above it; default the mark's label."),
        ], required: ["mark"])
    }

    /// Its result names the mark in the screen's own words, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Names the label when given, else the mark.
    func activity(for input: ToolInput) -> String {
        input.string("label").map { "Pointing at \"\($0)\"" } ?? "Pointing at mark \(input.integer("mark") ?? 0)"
    }

    /// Looks up the mark and draws a highlight, label and pointer on it.
    func run(_ input: ToolInput) async throws -> String {
        guard let number = input.integer("mark") else { throw ToolError("Pass mark, a number from look_at_screen.") }
        let mark = try marks.mark(number)
        let frame = mark.target.frame
        var shapes: [OverlayShape] = [.highlight(frame)]
        if let text = input.string("label") ?? (mark.target.label.isEmpty ? nil : mark.target.label) {
            shapes.append(.label(String(text.prefix(DrawingRequest.textLimit)), at: CGPoint(x: frame.midX, y: frame.minY)))
        }
        shapes.append(.pointer(mark.center))
        _ = try await show(shapes, on: overlay, for: .seconds(DrawingRequest.defaultSeconds))
        return "Pointing at \(mark.name) at x \(Int(frame.minX)), y \(Int(frame.minY)), \(Int(frame.width)) × \(Int(frame.height)) points."
    }
}

/// Draws `shapes`, given in points from the top-left of the main screen, on `overlay` for `duration`; returns the main screen's size.
@MainActor
private func show(_ shapes: [OverlayShape], on overlay: ScreenOverlay, for duration: Duration) throws -> CGSize {
    guard let mainScreen = NSScreen.screens.first else { throw ToolError("No display is connected.") }
    let height = mainScreen.frame.height
    overlay.draw(shapes.map { $0.mapped { OverlayCoordinates.appKitPoint(fromTopLeft: $0, mainScreenHeight: height) } }, duration: duration)
    return mainScreen.frame.size
}
