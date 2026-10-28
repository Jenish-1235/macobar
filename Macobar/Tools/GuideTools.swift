import CoreGraphics

/// Waits for the user to do one step of a guided walkthrough, then reports what they did.
struct WaitForUserTool: Tool {
    /// What the model can ask to wait for.
    private enum Expect: String, CaseIterable {
        /// A click inside `rect`.
        case clickIn = "click_in"
        /// Another app coming to the front.
        case appChange = "app_change"
        /// The front window changing.
        case windowChange = "window_change"
        /// A menu opening.
        case menuOpen = "menu_open"
        /// `text` showing in the front window.
        case textAppears = "text_appears"
        /// Any key press.
        case anyKey = "any_key"
    }

    /// Name the model calls it by.
    let name = "wait_for_user"
    /// When to call it and what it returns.
    let description = """
        Waits for the user to do one step of a guided walkthrough. First point at the target (point_at_element, \
        point_at_mark or draw_on_screen) and say what to do in one short sentence, then call this. click_in needs \
        rect: the frame the pointing tool returned. If it times out, offer to do it for them.
        """

    /// Takes what to expect, its rect or text, and an optional timeout.
    var parameters: JSONValue {
        Schema.object([
            "expect": Schema.oneOf(Expect.allCases.map(\.rawValue), "What the user does next."),
            "rect": Schema.object([
                "x": Schema.number("Left edge, screen points."),
                "y": Schema.number("Top edge, from the top."),
                "width": Schema.number("Width."),
                "height": Schema.number("Height."),
            ], required: ["x", "y", "width", "height"]),
            "text": Schema.string("For text_appears: text that shows in the front window."),
            "timeout_seconds": Schema.number("Default 60, at most 300."),
        ], required: ["expect"])
    }

    /// A window change reports the new window's title, which a web page or file chose.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        Expect(rawValue: input.string("expect") ?? "") == .windowChange
    }

    /// Names what is being waited for.
    func activity(for input: ToolInput) -> String {
        guard let expectation = try? Self.expectation(from: input) else { return "Waiting for you" }
        return "Waiting for \(expectation.summary)"
    }

    /// Watches for the step and reports whether the user did it in time.
    func run(_ input: ToolInput) async throws -> String {
        let expectation = try Self.expectation(from: input)
        let timeout = UserProgressWaiter.timeout(seconds: input.number("timeout_seconds"))
        switch try await UserProgressWaiter.wait(for: expectation, timeout: timeout) {
        case .matched(let happening):
            return "Step done: \(happening). Go on to the next step."
        case .timedOut:
            return "The user didn't do it within \(timeout.components.seconds) seconds (waited for \(expectation.summary)). Offer to do it for them."
        case .cancelled:
            return "Stopped waiting for \(expectation.summary)."
        }
    }

    /// The expectation `input` describes, or an error saying which argument to fix.
    static func expectation(from input: ToolInput) throws -> UserExpectation {
        let expectName = try input.requiredString("expect")
        guard let expect = Expect(rawValue: expectName) else {
            throw ToolError("Unknown expect \"\(expectName)\". Use one of: \(Expect.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        switch expect {
        case .clickIn: return .clickIn(try area(from: input))
        case .appChange: return .appChange
        case .windowChange: return .windowChange
        case .menuOpen: return .menuOpen
        case .textAppears:
            guard let text = input.string("text") else { throw ToolError("text_appears needs text: the words to watch for.") }
            return .textAppears(text)
        case .anyKey: return .anyKey
        }
    }

    /// The click target in `input`'s rect, which must have a positive size.
    private static func area(from input: ToolInput) throws -> CGRect {
        let rect = input.arguments["rect"]
        guard let x = rect?["x"]?.number, let y = rect?["y"]?.number,
              let width = rect?["width"]?.number, let height = rect?["height"]?.number, width > 0, height > 0
        else {
            throw ToolError("click_in needs rect {x, y, width, height} with a positive size, in screen points from the top-left of the main display.")
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
