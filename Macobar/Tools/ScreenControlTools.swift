import ApplicationServices

/// Shows the model the screen with a numbered mark on everything it can point at or act on.
struct LookAtScreenTool: VisualTool {
    /// Where the marks are kept for click_mark, scroll and drag.
    private let marks: ScreenMarkStore

    /// Name the model calls it by.
    let name = "look_at_screen"
    /// When to call it and what it returns.
    let description = """
        Shows you the screen with numbered marks on every control and text, listed like `12 button 'Export' at \
        (840,112,64,22)` (x, y, width, height in points from the main display's top-left). Use it to act on things, \
        especially in web pages and Electron apps where list_ui_elements sees little; pass marks to click_mark, \
        scroll and drag. Marks expire after 2 minutes or the next look. Never captures macobar.
        """

    /// Creates the tool, keeping its marks in `marks`.
    init(marks: ScreenMarkStore) {
        self.marks = marks
    }

    /// Takes the target.
    var parameters: JSONValue {
        Schema.object([
            "target": Schema.oneOf(LookTarget.allCases.map(\.rawValue), "Default screen (the pointer's display) or front_window."),
        ])
    }

    /// Seeing the screen can expose private data, so it asks first.
    func risk(for input: ToolInput) -> ToolRisk { .confirmOnce }

    /// Its result shows the screen's content, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Names what is being looked at.
    func activity(for input: ToolInput) -> String {
        input.string("target") == LookTarget.frontWindow.rawValue ? "Looking at the front window" : "Looking at the screen"
    }

    /// Captures the target, marks it, and returns the marked image with the list of marks.
    func look(_ input: ToolInput) async throws -> (text: String, images: [ToolImage]) {
        let targetName = input.string("target") ?? LookTarget.screen.rawValue
        guard let target = LookTarget(rawValue: targetName) else {
            throw ToolError("Unknown target \"\(targetName)\". Use one of: \(LookTarget.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        let look = try await ScreenMarks.look(at: target, storingIn: marks)
        let area = look.area.integral
        let header = "The image shows \(look.subject): screen points (\(Int(area.minX)),\(Int(area.minY)),\(Int(area.width)),\(Int(area.height)))."
        guard !look.marks.isEmpty else { return (header + " Nothing in it could be marked.", [look.image]) }
        return (header + " Marks:\n" + look.marks.map(\.summary).joined(separator: "\n"), [look.image])
    }
}

/// Clicks a mark from look_at_screen, or a point, with the real mouse.
struct ClickMarkTool: Tool {
    /// Most clicks in one call: a double-click.
    private static let maximumCount = 2

    /// Where look_at_screen keeps its marks.
    private let marks: ScreenMarkStore

    /// Name the model calls it by.
    let name = "click_mark"
    /// When to call it and what it returns.
    let description = """
        Clicks a look_at_screen mark (or x and y) in any app: buttons, links, rows, fields (then use type_text). Look \
        again to check the result.
        """

    /// Creates the tool, finding marks in `marks`.
    init(marks: ScreenMarkStore) {
        self.marks = marks
    }

    /// Takes the mark or point, the button and the click count.
    var parameters: JSONValue {
        Schema.object(PointReference.parameters(place: "the place to click").merging([
            "button": Schema.oneOf(MouseEvents.Button.allCases.map(\.rawValue), "Default left; right opens a context menu."),
            "count": Schema.integer("1 (default) or 2 for a double-click."),
        ]) { first, _ in first })
    }

    /// Clicking can change or submit things, so it asks first.
    func risk(for input: ToolInput) -> ToolRisk { .confirmOnce }

    /// Its result names marks in the screen's own words, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Names the click and its place, e.g. "Clicking 'Export'".
    func activity(for input: ToolInput) -> String {
        let verb = switch (input.string("button"), input.integer("count")) {
        case (MouseEvents.Button.right.rawValue?, _): "Right-clicking"
        case (_, 2?): "Double-clicking"
        default: "Clicking"
        }
        let place = (try? PointReference.optional(in: input))?.map { $0.name(in: marks) } ?? "on screen"
        return "\(verb) \(place)"
    }

    /// Presses an Accessibility-backed mark directly when it can; otherwise moves the mouse there and clicks.
    func run(_ input: ToolInput) async throws -> String {
        let reference = try PointReference.required(in: input)
        let buttonName = input.string("button") ?? MouseEvents.Button.left.rawValue
        guard let button = MouseEvents.Button(rawValue: buttonName) else {
            throw ToolError("Unknown button \"\(buttonName)\". Use left or right.")
        }
        let count = input.integer("count") ?? 1
        guard (1...Self.maximumCount).contains(count) else { throw ToolError("count must be 1 or 2.") }
        try AccessibilityElement.requirePermission()
        let (point, mark) = try reference.resolve(in: marks)
        try await MouseEvents.requireActionable(point)
        let place = reference.name(in: marks)
        if button == .left, count == 1, let mark, mark.target.source == .accessibility, Self.press(mark) {
            return "Pressed \(place)."
        }
        try await MouseEvents.click(button, count: count, at: point)
        let verb = button == .right ? "Right-clicked" : count == 2 ? "Double-clicked" : "Clicked"
        return "\(verb) \(place) at (\(Int(point.x)), \(Int(point.y)))."
    }

    /// Presses the element under `mark`'s centre (or a near ancestor) when it is the same kind and supports pressing; never one of macobar's own, such as an approval card that appeared there since the look.
    private static func press(_ mark: ScreenMark) -> Bool {
        var hit: AXUIElement?
        var hitProcess: pid_t = 0
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(mark.center.x), Float(mark.center.y), &hit) == .success,
              let hit, AXUIElementGetPid(hit, &hitProcess) == .success,
              hitProcess != ProcessInfo.processInfo.processIdentifier else { return false }
        var candidate: AccessibilityElement? = AccessibilityElement(element: hit)
        for _ in 0..<3 {
            guard let element = candidate else { return false }
            if let role = element.role, MarkKind(role: role, subrole: element.attribute(kAXSubroleAttribute)) == mark.target.kind {
                var actionNames: CFArray?
                AXUIElementCopyActionNames(element.element, &actionNames)
                guard (actionNames as? [String] ?? []).contains(kAXPressAction) else { return false }
                return (try? element.perform(kAXPressAction)) != nil
            }
            candidate = element.elementAttribute(kAXParentAttribute)
        }
        return false
    }
}

/// Scrolls the content under a mark, a point, or the pointer.
struct ScrollTool: Tool {
    /// Most lines in one call, so a typo can't fling a page.
    private static let maximumLines = 50

    /// Where look_at_screen keeps its marks.
    private let marks: ScreenMarkStore

    /// Name the model calls it by.
    let name = "scroll"
    /// When to call it and what it returns.
    let description = """
        Scrolls over a look_at_screen mark (or x and y, or the pointer) in any app. Look again afterwards, since \
        everything moves.
        """

    /// Creates the tool, finding marks in `marks`.
    init(marks: ScreenMarkStore) {
        self.marks = marks
    }

    /// Takes the direction, the amount and an optional place.
    var parameters: JSONValue {
        Schema.object(PointReference.parameters(place: "the area to scroll").merging([
            "direction": Schema.oneOf(MouseEvents.ScrollDirection.allCases.map(\.rawValue), "Direction."),
            "amount": Schema.integer("Lines, 1–\(Self.maximumLines). Default 5."),
        ]) { first, _ in first }, required: ["direction"])
    }

    /// Scrolling moves the pointer and can trigger app actions, so it asks first.
    func risk(for input: ToolInput) -> ToolRisk { .confirmOnce }

    /// Its result names marks in the screen's own words, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Names the direction and place, e.g. "Scrolling down over 'Inbox'".
    func activity(for input: ToolInput) -> String {
        let place = (try? PointReference.optional(in: input))?.map { " over \($0.name(in: marks))" } ?? ""
        return "Scrolling \(input.string("direction") ?? "the page")\(place)"
    }

    /// Moves the pointer to the place, if given, and scrolls there.
    func run(_ input: ToolInput) async throws -> String {
        let directionName = try input.requiredString("direction")
        guard let direction = MouseEvents.ScrollDirection(rawValue: directionName) else {
            throw ToolError("Unknown direction \"\(directionName)\". Use up, down, left or right.")
        }
        let lines = input.integer("amount") ?? 5
        guard (1...Self.maximumLines).contains(lines) else { throw ToolError("amount must be 1 to \(Self.maximumLines) lines.") }
        try AccessibilityElement.requirePermission()
        let reference = try PointReference.optional(in: input)
        guard let point = try reference?.resolve(in: marks).point ?? MouseEvents.pointerLocation else {
            throw ToolError("Couldn't find the pointer. Pass a mark from look_at_screen, or x and y.")
        }
        try await MouseEvents.requireActionable(point)
        try await MouseEvents.scroll(direction, lines: lines, at: point)
        let place = reference.map { " over \($0.name(in: marks))" } ?? ""
        return "Scrolled \(direction.rawValue) \(lines) lines\(place)."
    }
}

/// Drags with the real mouse from one mark or point to another.
struct DragTool: Tool {
    /// Where look_at_screen keeps its marks.
    private let marks: ScreenMarkStore

    /// Name the model calls it by.
    let name = "drag"
    /// When to call it and what it returns.
    let description = """
        Drags with the mouse from one look_at_screen mark (or x and y) to another, e.g. files onto folders, sliders, \
        text selection. Look again afterwards.
        """

    /// Creates the tool, finding marks in `marks`.
    init(marks: ScreenMarkStore) {
        self.marks = marks
    }

    /// Takes where to start and where to drop.
    var parameters: JSONValue {
        Schema.object(PointReference.parameters(prefix: "from_", place: "the place to drag from")
            .merging(PointReference.parameters(prefix: "to_", place: "the place to drop")) { first, _ in first })
    }

    /// Dragging moves and rearranges things, so it asks first.
    func risk(for input: ToolInput) -> ToolRisk { .confirmOnce }

    /// Its result names marks in the screen's own words, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Names both places, e.g. "Dragging 'report.pdf' to 'Archive'".
    func activity(for input: ToolInput) -> String {
        let start = (try? PointReference.optional(in: input, prefix: "from_"))?.map { $0.name(in: marks) } ?? "something"
        let end = (try? PointReference.optional(in: input, prefix: "to_"))?.map { $0.name(in: marks) } ?? "somewhere"
        return "Dragging \(start) to \(end)"
    }

    /// Presses at the start, moves in small steps to the end, and releases there.
    func run(_ input: ToolInput) async throws -> String {
        let startReference = try PointReference.required(in: input, prefix: "from_")
        let endReference = try PointReference.required(in: input, prefix: "to_")
        try AccessibilityElement.requirePermission()
        let start = try startReference.resolve(in: marks).point
        let end = try endReference.resolve(in: marks).point
        try await MouseEvents.requireActionable(start)
        try await MouseEvents.requireActionable(end)
        try await MouseEvents.drag(from: start, to: end)
        return "Dragged \(startReference.name(in: marks)) to \(endReference.name(in: marks))."
    }
}
