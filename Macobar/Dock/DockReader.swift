import AppKit
import ApplicationServices

/// Reads the Dock's current layout through the Accessibility API.
@MainActor
final class DockReader {
    /// Accessibility subrole the Dock gives its spacer tiles.
    private static let spacerSubrole = "AXSpacerDockItem"
    /// Longest a single Accessibility call may block, so a restarting Dock can't freeze the UI.
    private static let messagingTimeout: Float = 0.25
    /// Accessibility handle for the running Dock, replaced whenever the Dock restarts.
    private var dockApplication: (processIdentifier: pid_t, element: AXUIElement)?

    /// Returns where the Dock and gap are now, or nil if the Dock or gap can't be read.
    func readGeometry() -> DockGeometry? {
        guard let list = dockItemList(), let listFrame = frame(of: list) else { return nil }
        let items = children(of: list).compactMap(dockItem)
        return DockGeometry(dockFrame: listFrame, items: items)
    }

    /// The Dock's item list, the container that holds every tile.
    private func dockItemList() -> AXUIElement? {
        guard let application = dockApplicationElement() else { return nil }
        return children(of: application).first { stringValue(of: $0, kAXRoleAttribute) == kAXListRole }
    }

    /// The Dock's application element, recreated when its process changes.
    private func dockApplicationElement() -> AXUIElement? {
        guard let dock = DockProcess.running else { return nil }
        if dockApplication?.processIdentifier != dock.processIdentifier {
            let element = AXUIElementCreateApplication(dock.processIdentifier)
            AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
            dockApplication = (dock.processIdentifier, element)
        }
        return dockApplication?.element
    }

    /// Converts one tile into a DockItem using a single batched attribute read.
    private func dockItem(from element: AXUIElement) -> DockItem? {
        let attributes = [kAXSubroleAttribute, kAXPositionAttribute, kAXSizeAttribute] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, attributes, [], &values) == .success,
              let values = values as? [AnyObject], values.count == 3,
              let frame = screenFrame(position: values[1], size: values[2]) else { return nil }
        return DockItem(isSpacer: values[0] as? String == Self.spacerSubrole, frame: frame)
    }

    /// Reads an element's on-screen frame.
    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(of: element, kAXPositionAttribute),
              let size = attribute(of: element, kAXSizeAttribute) else { return nil }
        return screenFrame(position: position, size: size)
    }

    /// Builds an AppKit screen frame from Accessibility position and size values.
    private func screenFrame(position: AnyObject, size: AnyObject) -> CGRect? {
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard let positionValue = axValue(position), AXValueGetValue(positionValue, .cgPoint, &origin),
              let sizeValue = axValue(size), AXValueGetValue(sizeValue, .cgSize, &extent),
              let primaryScreen = NSScreen.screens.first else { return nil }
        return CGRect(origin: origin, size: extent).flippedVertically(withinHeight: primaryScreen.frame.height)
    }

    /// An element's children, or none.
    private func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(of: element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    /// An element's attribute as a string, or nil.
    private func stringValue(of element: AXUIElement, _ name: String) -> String? {
        attribute(of: element, name) as? String
    }

    /// Reads one raw attribute value.
    private func attribute(of element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    /// Casts a raw value to AXValue after checking its Core Foundation type.
    private func axValue(_ object: AnyObject) -> AXValue? {
        guard CFGetTypeID(object) == AXValueGetTypeID() else { return nil }
        return (object as! AXValue)
    }
}
