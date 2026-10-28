import ApplicationServices

/// Finds the actionable and text-bearing elements in a window, with their on-screen frames.
enum AccessibilityTargets {
    /// One element's attributes, read in a single round trip.
    private struct ElementAttributes {
        /// Attributes read for each element, in the order of the stored properties.
        static let names = [
            kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
            kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute,
        ]

        /// Role, e.g. `AXButton`.
        let role: String?
        /// Subrole, e.g. `AXTabButton`.
        let subrole: String?
        /// Title, description or (for text) value: what it says.
        let label: String
        /// On-screen frame in screen points.
        let frame: CGRect?
        /// Child elements.
        let children: [AXUIElement]

        /// Reads `element`'s attributes, or nil when the app doesn't answer.
        init?(_ element: AXUIElement) {
            var values: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, Self.names as CFArray, [], &values) == .success,
                  let values = values as? [AnyObject], values.count == Self.names.count else { return nil }
            role = values[0] as? String
            subrole = values[1] as? String
            let title = values[2] as? String
            let description = values[3] as? String
            let value = values[4] as? String
            let texts = role == kAXStaticTextRole ? [value, title, description] : [title, description]
            label = texts.compactMap(\.self).first { !$0.isEmpty } ?? ""
            frame = AccessibilityTargets.frame(position: values[5], size: values[6])
            children = values[7] as? [AXUIElement] ?? []
        }
    }

    /// Most elements visited, so huge windows and web pages stay fast.
    private static let nodeLimit = 4_000

    /// The targets in `window` that show inside `visibleArea` (screen points), leaving out content scrolled out of view.
    static func targets(in window: AccessibilityElement, within visibleArea: CGRect) -> [ScreenTarget] {
        guard !visibleArea.isNull else { return [] }
        var targets: [ScreenTarget] = []
        var visitedCount = 0
        var pending: [(element: AXUIElement, clip: CGRect)] = [(window.element, visibleArea)]
        while let (element, clip) = pending.popLast(), visitedCount < nodeLimit {
            visitedCount += 1
            guard let attributes = ElementAttributes(element), let role = attributes.role else { continue }
            var childClip = clip
            if role == kAXScrollAreaRole, let frame = attributes.frame {
                childClip = clip.intersection(frame)
                guard !childClip.isNull else { continue }
            }
            if let target = target(from: attributes, role: role, clip: clip) {
                targets.append(target)
            }
            pending.append(contentsOf: attributes.children.reversed().map { ($0, childClip) })
        }
        return targets
    }

    /// `window`'s frame in screen points, when the app reports it.
    static func frame(of window: AccessibilityElement) -> CGRect? {
        guard let position: AnyObject = window.attribute(kAXPositionAttribute), let size: AnyObject = window.attribute(kAXSizeAttribute) else { return nil }
        return frame(position: position, size: size)
    }

    /// A target for an element worth marking whose frame shows inside `clip`, cut to that visible part.
    private static func target(from attributes: ElementAttributes, role: String, clip: CGRect) -> ScreenTarget? {
        guard let kind = MarkKind(role: role, subrole: attributes.subrole), let frame = attributes.frame?.intersection(clip),
              !frame.isNull, !frame.isEmpty else { return nil }
        if kind == .text, attributes.label.isEmpty || attributes.label.count > ScreenTarget.labelLimit { return nil }
        return ScreenTarget(kind: kind, label: attributes.label, frame: frame, source: .accessibility)
    }

    /// A frame from Accessibility position and size values, or nil when either is missing.
    private static func frame(position: AnyObject, size: AnyObject) -> CGRect? {
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard let positionValue = axValue(position), AXValueGetValue(positionValue, .cgPoint, &origin),
              let sizeValue = axValue(size), AXValueGetValue(sizeValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    /// `object` as an AXValue, after checking its Core Foundation type.
    private static func axValue(_ object: AnyObject) -> AXValue? {
        guard CFGetTypeID(object) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(object, to: AXValue.self)
    }
}
