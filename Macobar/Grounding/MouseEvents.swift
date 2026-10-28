import AppKit

/// Posts real mouse events at screen points (click, scroll, drag), putting the pointer back afterwards.
enum MouseEvents {
    /// Which mouse button clicks.
    enum Button: String, CaseIterable, Sendable {
        /// The primary button.
        case left
        /// The secondary button, for context menus.
        case right
    }

    /// Which way to scroll the content.
    enum ScrollDirection: String, CaseIterable, Sendable {
        /// Towards the top.
        case up
        /// Towards the bottom.
        case down
        /// Towards the left edge.
        case left
        /// Towards the right edge.
        case right

        /// One line of scrolling as scroll-wheel deltas: positive is up or left.
        var lineDeltas: (vertical: Int32, horizontal: Int32) {
            switch self {
            case .up: (1, 0)
            case .down: (-1, 0)
            case .left: (0, 1)
            case .right: (0, -1)
            }
        }
    }

    /// Steps in one drag, so apps see a smooth movement.
    static let dragSteps = 20
    /// Pause between events so apps register each one.
    private static let eventDelay = Duration.milliseconds(30)
    /// Pause between drag or scroll steps.
    private static let stepDelay = Duration.milliseconds(12)

    /// Throws unless `point` is on a display and outside macobar's own windows.
    @MainActor
    static func requireActionable(_ point: CGPoint) throws {
        var displayCount: UInt32 = 0
        CGGetDisplaysWithPoint(point, 0, nil, &displayCount)
        guard displayCount > 0 else {
            throw ToolError("Point (\(Int(point.x)), \(Int(point.y))) is off screen. Use a mark, or x and y from look_at_screen's list.")
        }
        guard let mainScreenHeight = NSScreen.screens.first?.frame.height else { return }
        let appKitPoint = ScreenCoordinates.appKitPoint(for: point, mainScreenHeight: mainScreenHeight)
        guard !NSApplication.shared.windows.contains(where: { $0.isVisible && !$0.ignoresMouseEvents && $0.frame.contains(appKitPoint) }) else {
            throw ToolError("That spot is inside macobar's own window, which Macie never clicks. Choose a place in another app.")
        }
    }

    /// Clicks `button` `count` times at `point`.
    static func click(_ button: Button, count: Int, at point: CGPoint) async throws {
        let (down, up, mouseButton): (CGEventType, CGEventType, CGMouseButton) = switch button {
        case .left: (.leftMouseDown, .leftMouseUp, .left)
        case .right: (.rightMouseDown, .rightMouseUp, .right)
        }
        try await withPointerRestored {
            try post(.mouseMoved, at: point)
            try await Task.sleep(for: eventDelay)
            for clickState in 1...Int64(count) {
                try await pressAndRelease(down, up, at: point, button: mouseButton, clickState: clickState)
            }
            try await Task.sleep(for: eventDelay)
        }
    }

    /// Where the pointer is now, in screen points, or nil when the system won't say.
    static var pointerLocation: CGPoint? {
        CGEvent(source: nil)?.location
    }

    /// Scrolls `lines` lines in `direction` with the pointer over `point`.
    static func scroll(_ direction: ScrollDirection, lines: Int, at point: CGPoint) async throws {
        try await withPointerRestored {
            try post(.mouseMoved, at: point)
            try await Task.sleep(for: eventDelay)
            let deltas = direction.lineDeltas
            for _ in 0..<lines {
                guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                                          wheel1: deltas.vertical, wheel2: deltas.horizontal, wheel3: 0) else {
                    throw ToolError("Couldn't create a scroll event.")
                }
                event.post(tap: .cghidEventTap)
                try await Task.sleep(for: stepDelay)
            }
        }
    }

    /// Presses the left button at `start`, moves to `end` in `dragSteps` steps, and releases it there; when cancelled
    /// partway, or when a macobar window has appeared at `end`, releases it back at `start` so the button is never left
    /// held and nothing is dropped halfway or onto macobar.
    static func drag(from start: CGPoint, to end: CGPoint) async throws {
        try await withPointerRestored {
            try post(.mouseMoved, at: start)
            try await Task.sleep(for: eventDelay)
            try await pressIfActionable(at: start)
            do {
                try await Task.sleep(for: eventDelay)
                for point in path(from: start, to: end, steps: dragSteps) {
                    try post(.leftMouseDragged, at: point)
                    try await Task.sleep(for: stepDelay)
                }
            } catch {
                try? post(.leftMouseUp, at: start)
                throw error
            }
            try await releaseIfActionable(at: end, elseAt: start)
            try await Task.sleep(for: eventDelay)
        }
    }

    /// `steps` evenly spaced points from just after `start` to exactly `end`.
    static func path(from start: CGPoint, to end: CGPoint, steps: Int) -> [CGPoint] {
        (1...max(steps, 1)).map { step in
            let progress = CGFloat(step) / CGFloat(max(steps, 1))
            return CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress)
        }
    }

    /// Checks `point` and posts `down` then `up` there in one main-actor step, so a macobar window (an approval card) that appeared since the tool's own check can't take the click.
    @MainActor
    private static func pressAndRelease(_ down: CGEventType, _ up: CGEventType, at point: CGPoint, button: CGMouseButton, clickState: Int64) throws {
        try requireActionable(point)
        try post(down, at: point, button: button, clickState: clickState)
        try post(up, at: point, button: button, clickState: clickState)
    }

    /// Checks `point` and presses the left button there in one main-actor step, for the start of a drag.
    @MainActor
    private static func pressIfActionable(at point: CGPoint) throws {
        try requireActionable(point)
        try post(.leftMouseDown, at: point)
    }

    /// Releases the left button at `end` after checking it in the same main-actor step; when `end` is now off screen or in a macobar window, releases at `fallback` instead and throws.
    @MainActor
    private static func releaseIfActionable(at end: CGPoint, elseAt fallback: CGPoint) throws {
        do {
            try requireActionable(end)
        } catch {
            try? post(.leftMouseUp, at: fallback)
            throw error
        }
        try post(.leftMouseUp, at: end)
    }

    /// Runs `body`, then moves the pointer back to where it was, even when `body` fails.
    private static func withPointerRestored(_ body: () async throws -> Void) async throws {
        let original = pointerLocation
        defer {
            if let original { try? post(.mouseMoved, at: original) }
        }
        try await body()
    }

    /// Posts one mouse event of `type` at `point` to the system, as if from the real mouse.
    private static func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton = .left, clickState: Int64 = 1) throws {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: ScreenCoordinates.eventLocation(for: point), mouseButton: button) else {
            throw ToolError("Couldn't create a mouse event.")
        }
        event.setIntegerValueField(.mouseEventClickState, value: clickState)
        event.post(tap: .cghidEventTap)
    }
}
