import AppKit
import ApplicationServices

/// Reports what the user is looking at: the frontmost app, its window, and the selection.
struct FrontmostContextTool: Tool {
    /// Most selected-text characters returned.
    private static let selectionLimit = 15_000

    /// Name the model calls it by.
    let name = "get_frontmost_context"
    /// When to call it and what it returns.
    let description = """
        Returns the frontmost app, window title, focused element and selected text. Call it first when the user means \
        "this", "it", the current app, window or selection.
        """

    /// Takes no arguments.
    var parameters: JSONValue { Schema.object() }

    /// Its result carries outside text the model will read, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Describes the lookup.
    func activity(for input: ToolInput) -> String { "Looking at the frontmost app" }

    /// Reads the frontmost app, window title, focused role and selection.
    func run(_ input: ToolInput) async throws -> String {
        let app = try RunningApps.find(nil)
        var lines = ["App: \(app.localizedName ?? "Unknown") (\(app.bundleIdentifier ?? "no bundle ID"))"]
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return (lines + ["macobar's own windows (settings, the sharing token) are never read."]).joined(separator: "\n")
        }
        guard AXIsProcessTrusted() else {
            lines.append("Window and selection are unavailable: macobar needs Accessibility permission.")
            return lines.joined(separator: "\n")
        }
        let root = AccessibilityElement.application(app)
        if let title = root.elementAttribute(kAXFocusedWindowAttribute)?.title, !title.isEmpty {
            lines.append("Window: \(title)")
        }
        if let focused = root.elementAttribute(kAXFocusedUIElementAttribute) {
            if let role = focused.role { lines.append("Focused element: \(role)") }
            if let selection: String = focused.attribute(kAXSelectedTextAttribute), !selection.isEmpty {
                lines.append("Selected text:\n\(selection.prefix(Self.selectionLimit))")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// Reads the text shown in an app's front window.
struct ReadWindowTool: Tool {
    /// Roles whose value is text worth reading.
    private static let textRoles: Set<String> = [kAXStaticTextRole, kAXTextAreaRole, kAXTextFieldRole]
    /// Most elements visited, so huge windows stay fast.
    private static let nodeLimit = 2_000
    /// Most characters returned.
    private static let characterLimit = 15_000

    /// Name the model calls it by.
    let name = "read_window_text"
    /// When to call it and what it returns.
    let description = """
        Reads the visible text of an app's front window. Call it when the user asks what's on screen or in a window.
        """

    /// Takes an optional app name.
    var parameters: JSONValue {
        Schema.object(["app": Schema.string("Default: frontmost app.")])
    }

    /// Its result carries outside text the model will read, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Names the app being read.
    func activity(for input: ToolInput) -> String {
        "Reading \(input.string("app").map { "\($0)'s" } ?? "the front") window"
    }

    /// Walks the window's elements depth-first, collecting their text.
    func run(_ input: ToolInput) async throws -> String {
        let window = try AccessibilityElement.focusedWindow(of: appOtherThanMacobar(named: input.string("app")))
        var lines = ["Window: \(window.title ?? "Untitled")", ""]
        var characterCount = 0
        var visitedCount = 0
        var pending = Array(window.children.reversed())
        while let element = pending.popLast(), visitedCount < Self.nodeLimit, characterCount < Self.characterLimit {
            visitedCount += 1
            for text in Self.texts(of: element) where text != lines.last {
                lines.append(text)
                characterCount += text.count + 1
            }
            pending.append(contentsOf: element.children.reversed())
        }
        let text = lines.joined(separator: "\n")
        return text.count > Self.characterLimit ? "\(text.prefix(Self.characterLimit))\n… (truncated)" : text
    }

    /// The non-empty title, description and (for text roles other than password fields) value of `element`.
    private static func texts(of element: AccessibilityElement) -> [String] {
        let value = element.role.map(textRoles.contains) == true && !isSecureTextField(element) ? element.value : nil
        return [element.title, element.label, value]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
