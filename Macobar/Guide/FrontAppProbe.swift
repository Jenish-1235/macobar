import AppKit
import ApplicationServices

/// Reads the frontmost app's state through Accessibility: its window, an open menu, and the text it shows.
enum FrontAppProbe {
    /// Most elements visited when searching a window for text, so huge windows stay fast.
    private static let nodeLimit = 3_000

    /// The window the user is working in within the frontmost app, if any; never one of macobar's own, so a wait can't probe them.
    static func frontWindow() -> AccessibilityElement? {
        (try? appOtherThanMacobar(named: nil)).flatMap { try? AccessibilityElement.focusedWindow(of: $0) }
    }

    /// The menu open in the frontmost app, e.g. "the File menu" or "a menu", or nil when none is.
    static func openMenu() -> String? {
        guard let app = RunningApps.frontmost else { return nil }
        let root = AccessibilityElement.application(app)
        let menuBarItems = root.elementAttribute(kAXMenuBarAttribute)?.children ?? []
        if let item = menuBarItems.first(where: { $0.attribute(kAXSelectedAttribute) as Bool? == true }) {
            return item.title.flatMap { $0.isEmpty ? nil : "the \($0) menu" } ?? "a menu"
        }
        let focusedRole = root.elementAttribute(kAXFocusedUIElementAttribute)?.role
        return focusedRole == kAXMenuRole || focusedRole == kAXMenuItemRole ? "a menu" : nil
    }

    /// Whether `text` shows anywhere in the frontmost app's window, as an element's title, value (never a password field's) or description; stops early when the task is cancelled.
    static func frontWindowContains(_ text: String) -> Bool {
        guard let window = frontWindow() else { return false }
        var pending = [window]
        var visitedCount = 0
        while let element = pending.popLast(), visitedCount < nodeLimit, !Task.isCancelled {
            visitedCount += 1
            let value = isSecureTextField(element) ? nil : element.value
            if [element.title, value, element.label].contains(where: { $0?.localizedCaseInsensitiveContains(text) == true }) {
                return true
            }
            pending.append(contentsOf: element.children)
        }
        return false
    }
}
