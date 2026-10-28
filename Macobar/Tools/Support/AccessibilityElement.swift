import ApplicationServices
import AppKit

/// A thin wrapper over an Accessibility element for reading and acting on other apps' UI.
struct AccessibilityElement {
    /// The underlying element.
    let element: AXUIElement

    /// The root element of `app`.
    static func application(_ app: NSRunningApplication) -> AccessibilityElement {
        AccessibilityElement(element: AXUIElementCreateApplication(app.processIdentifier))
    }

    /// Throws an actionable error unless macobar may read and control other apps.
    static func requirePermission() throws {
        guard AXIsProcessTrusted() else {
            throw ToolError("macobar needs Accessibility permission (System Settings › Privacy & Security › Accessibility).")
        }
    }

    /// The window the user is working in within `app` (focused, else main); throws without permission or a window.
    static func focusedWindow(of app: NSRunningApplication) throws -> AccessibilityElement {
        try requirePermission()
        let root = application(app)
        guard let window = root.elementAttribute(kAXFocusedWindowAttribute) ?? root.elementAttribute(kAXMainWindowAttribute) else {
            throw ToolError("\(app.localizedName ?? "That app") has no open window.")
        }
        return window
    }

    /// The value of `attribute`, if present and of type `T`.
    func attribute<T>(_ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// The element-valued `attribute`, e.g. the focused window.
    func elementAttribute(_ attribute: String) -> AccessibilityElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return AccessibilityElement(element: unsafeDowncast(value, to: AXUIElement.self))
    }

    /// Child elements, in on-screen order.
    var children: [AccessibilityElement] {
        let elements: [AXUIElement]? = attribute(kAXChildrenAttribute)
        return (elements ?? []).map(AccessibilityElement.init)
    }

    /// Role, e.g. `AXButton`.
    var role: String? { attribute(kAXRoleAttribute) }
    /// Title, e.g. a button's label.
    var title: String? { attribute(kAXTitleAttribute) }
    /// Value as text, when it is text.
    var value: String? { attribute(kAXValueAttribute) }
    /// Accessibility description, often the label of an icon button.
    var label: String? { attribute(kAXDescriptionAttribute) }

    /// Performs `action`, e.g. `kAXPressAction`; throws when the app refuses.
    func perform(_ action: String) throws {
        let result = AXUIElementPerformAction(element, action as CFString)
        guard result == .success else { throw ToolError("The app refused \(action) (\(result.rawValue)).") }
    }

    /// Sets `attribute` to `value`; throws when the app refuses.
    func set(_ attribute: String, to value: CFTypeRef) throws {
        let result = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        guard result == .success else { throw ToolError("The app refused to change \(attribute) (\(result.rawValue)).") }
    }
}
