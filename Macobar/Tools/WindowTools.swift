import AppKit
import ApplicationServices

/// Moves, resizes, minimizes or full-screens an app's front window.
struct ArrangeWindowTool: Tool {
    /// Where a window can be put.
    private enum Position: String, CaseIterable {
        /// Left half of the screen.
        case leftHalf = "left_half"
        /// Right half of the screen.
        case rightHalf = "right_half"
        /// Top half of the screen.
        case topHalf = "top_half"
        /// Bottom half of the screen.
        case bottomHalf = "bottom_half"
        /// The whole usable screen.
        case maximize
        /// Centered, keeping its size.
        case center
        /// Into the Dock.
        case minimize
        /// Its own full-screen space.
        case fullscreen

        /// How the activity line and result phrase this position.
        var phrase: String {
            switch self {
            case .leftHalf: "to the left half"
            case .rightHalf: "to the right half"
            case .topHalf: "to the top half"
            case .bottomHalf: "to the bottom half"
            case .maximize: "to fill the screen"
            case .center: "to the center"
            case .minimize: "into the Dock"
            case .fullscreen: "into full screen"
            }
        }
    }

    /// Name the model calls it by.
    let name = "arrange_window"
    /// When to call it and what it returns.
    let description = """
        Snaps an app's front window to a screen half, or maximizes, centers, minimizes or full-screens it.
        """

    /// Takes an optional app and the position.
    var parameters: JSONValue {
        Schema.object([
            "app": Schema.string("Default: frontmost app."),
            "position": Schema.oneOf(Position.allCases.map(\.rawValue), "Where to put it."),
        ], required: ["position"])
    }

    /// Names the app and where its window goes.
    func activity(for input: ToolInput) -> String {
        let owner = input.string("app").map { "\($0)'s" } ?? "the front"
        return "Moving \(owner) window \(Position(rawValue: input.string("position") ?? "")?.phrase ?? "into place")"
    }

    /// Applies the position to the app's focused window.
    func run(_ input: ToolInput) async throws -> String {
        let positionName = try input.requiredString("position")
        guard let position = Position(rawValue: positionName) else {
            throw ToolError("Unknown position \"\(positionName)\". Use one of: \(Position.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        let app = try RunningApps.find(input.string("app"))
        let window = try AccessibilityElement.focusedWindow(of: app)
        switch position {
        case .minimize:
            try window.set(kAXMinimizedAttribute, to: true as CFBoolean)
        case .fullscreen:
            try window.set("AXFullScreen", to: true as CFBoolean)
        default:
            guard let frame = Self.frame(of: window) else { throw ToolError("Couldn't read the window's position.") }
            let target = await Self.targetFrame(for: position, from: frame)
            var origin = target.origin
            var size = target.size
            guard let originValue = AXValueCreate(.cgPoint, &origin), let sizeValue = AXValueCreate(.cgSize, &size) else {
                throw ToolError("Couldn't describe the new window frame.")
            }
            try window.set(kAXPositionAttribute, to: originValue)
            try window.set(kAXSizeAttribute, to: sizeValue)
        }
        return "Moved \(app.localizedName ?? "the app")'s window \(position.phrase)."
    }

    /// The window's frame in Accessibility coordinates (top-left origin of the primary screen).
    private static func frame(of window: AccessibilityElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let originValue = axValue(window.attribute(kAXPositionAttribute)), AXValueGetValue(originValue, .cgPoint, &origin),
              let sizeValue = axValue(window.attribute(kAXSizeAttribute)), AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// `object` as an AXValue, after checking its Core Foundation type.
    private static func axValue(_ object: CFTypeRef?) -> AXValue? {
        guard let object, CFGetTypeID(object) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(object, to: AXValue.self)
    }

    /// Where a window at `frame` should go for `position`, on the screen it mostly covers; both in Accessibility coordinates.
    @MainActor
    private static func targetFrame(for position: Position, from frame: CGRect) -> CGRect {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return frame }
        let appKitFrame = frame.flippedVertically(withinHeight: primaryHeight)
        let screen = NSScreen.screens.max { overlapArea($0.frame, appKitFrame) < overlapArea($1.frame, appKitFrame) }
        guard let visible = screen?.visibleFrame else { return frame }
        let target: CGRect
        switch position {
        case .leftHalf: target = CGRect(x: visible.minX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .rightHalf: target = CGRect(x: visible.midX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .topHalf: target = CGRect(x: visible.minX, y: visible.midY, width: visible.width, height: visible.height / 2)
        case .bottomHalf: target = CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height / 2)
        case .center:
            let width = min(appKitFrame.width, visible.width)
            let height = min(appKitFrame.height, visible.height)
            target = CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
        case .maximize, .minimize, .fullscreen: target = visible
        }
        return target.flippedVertically(withinHeight: primaryHeight)
    }

    /// The area two rects share.
    private static func overlapArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let overlap = first.intersection(second)
        return overlap.isNull ? 0 : overlap.width * overlap.height
    }
}
