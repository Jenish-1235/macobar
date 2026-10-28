import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Replaces the user's selected text in an app with new text, right where it is.
struct ReplaceSelectionTool: Tool {
    /// How long the app gets to read the pasteboard after Cmd-V before the user's clipboard comes back.
    private static let pasteDelay = Duration.milliseconds(250)
    /// Times the value is re-read after an Accessibility change before the change counts as ignored; some apps (Chrome, Electron) apply it asynchronously.
    private static let readBackAttempts = 10
    /// Pause before each re-read.
    private static let readBackInterval = Duration.milliseconds(50)

    /// Name the model calls it by.
    let name = "replace_selection"
    /// When to call it and what it returns.
    let description = """
        Replaces the user's selected text in place ("make this more polite", "fix the grammar"). Read it first with \
        get_frontmost_context, then pass the replacement for the whole selection, not just the changed part.
        """

    /// Takes the replacement text and an optional app.
    var parameters: JSONValue {
        Schema.object([
            "text": Schema.string("Complete replacement text."),
            "app": Schema.string("Default: frontmost app."),
        ], required: ["text"])
    }

    /// Replacing text changes the user's documents, so it asks first.
    func risk(for input: ToolInput) -> ToolRisk { .confirmOnce }

    /// Names the target app and shows the new text, so the user approves what will actually be put in.
    func activity(for input: ToolInput) -> String {
        let replacing = "Replacing the selected text in \(input.string("app") ?? "the front app")"
        guard let text = input.rawString("text"), !text.isEmpty else { return replacing }
        return "\(replacing) with \(approvalPreview(of: text))"
    }

    /// Sets the selection through Accessibility when the app allows it, else pastes over it and restores the clipboard.
    func run(_ input: ToolInput) async throws -> String {
        guard let text = input.rawString("text"), !text.isEmpty else {
            throw ToolError("Missing required argument \"text\". To delete the selection, use press_keys with \"delete\".")
        }
        try AccessibilityElement.requirePermission()
        let app = try appOtherThanMacobar(named: input.string("app"))
        let appName = app.localizedName ?? "the app"
        if let result = try await Self.replaceThroughAccessibility(with: text, in: app, appName: appName) {
            return result
        }
        try await Self.paste(text, into: app.processIdentifier)
        return """
            Pasted the replacement in \(appName), which can't be confirmed: if nothing was selected it went in at the \
            cursor, and if the selection isn't editable nothing changed.
            """
    }

    /// Sets the focused element's selected text and reports the outcome, or nil when the value never changed, so pasting is safe.
    private static func replaceThroughAccessibility(with text: String, in app: NSRunningApplication, appName: String) async throws -> String? {
        guard let focused = AccessibilityElement.application(app).elementAttribute(kAXFocusedUIElementAttribute),
              let before = focused.value, isSettable(kAXSelectedTextAttribute, of: focused)
        else { return nil }
        if focused.attribute(kAXSelectedTextAttribute) as String? == text {
            return "The selected text in \(appName) already reads exactly that, so nothing changed."
        }
        guard (try? focused.set(kAXSelectedTextAttribute, to: text as CFString)) != nil else { return nil }
        for _ in 0..<readBackAttempts {
            try await Task.sleep(for: readBackInterval)
            guard let after = focused.value, after != before else { continue }
            return after.contains(text)
                ? "Replaced the selected text in \(appName)."
                : "Changed the selected text in \(appName), but couldn't confirm the new text. Check it with get_frontmost_context or read_window_text."
        }
        return nil
    }

    /// Puts `text` on the clipboard, sends Cmd-V to `pid`, then puts the user's clipboard back.
    private static func paste(_ text: String, into pid: pid_t) async throws {
        let staged = await stage(text)
        let pasted = Result { try postPaste(to: pid) }
        try? await Task.sleep(for: pasteDelay)
        await restore(staged.snapshot, ifUnchangedSince: staged.changeCount)
        try pasted.get()
    }

    /// Whether the app lets `attribute` of `element` be changed.
    private static func isSettable(_ attribute: String, of element: AccessibilityElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element.element, attribute as CFString, &settable) == .success && settable.boolValue
    }

    /// Saves the general pasteboard and puts `text` on it as plain text; returns what was saved and the change count after.
    @MainActor
    private static func stage(_ text: String) -> (snapshot: PasteboardSnapshot, changeCount: Int) {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard.pasteboardItems ?? [])
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return (snapshot, pasteboard.changeCount)
    }

    /// Puts `snapshot` back on the general pasteboard, unless something else was copied since `changeCount`.
    @MainActor
    private static func restore(_ snapshot: PasteboardSnapshot, ifUnchangedSince changeCount: Int) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == changeCount else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(snapshot.pasteboardItems)
    }

    /// Sends Cmd-V (down, then up) straight to `pid`.
    private static func postPaste(to pid: pid_t) throws {
        for isKeyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: isKeyDown) else {
                throw ToolError("Couldn't create a keyboard event.")
            }
            event.flags = .maskCommand
            event.postToPid(pid)
        }
    }
}

/// A copy of a pasteboard's items, every type of each in its original order, so they can be written back later.
struct PasteboardSnapshot {
    /// One type of data on an item.
    struct Representation {
        /// The data's type, e.g. plain text or RTF.
        let type: NSPasteboard.PasteboardType
        /// The data itself.
        let data: Data
    }

    /// Each item's representations, items and types in pasteboard order (richest type first).
    let items: [[Representation]]

    /// Copies the data of every type of every item in `pasteboardItems`.
    init(_ pasteboardItems: [NSPasteboardItem]) {
        items = pasteboardItems.map { item in
            item.types.compactMap { type in item.data(forType: type).map { Representation(type: type, data: $0) } }
        }
    }

    /// Fresh pasteboard items holding the copied data, ready to write back.
    var pasteboardItems: [NSPasteboardItem] {
        items.map { representations in
            let item = NSPasteboardItem()
            for representation in representations {
                item.setData(representation.data, forType: representation.type)
            }
            return item
        }
    }
}
