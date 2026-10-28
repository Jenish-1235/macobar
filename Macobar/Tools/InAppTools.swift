import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Lists the controls in an app's front window, each with an id `click_element` accepts.
struct ListUIElementsTool: Tool {
    /// Roles the user can click, toggle, pick or type into.
    private static let actionableRoles: Set<String> = [
        kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXPopUpButtonRole, kAXMenuButtonRole, kAXComboBoxRole,
        kAXTextFieldRole, kAXTextAreaRole, kAXDisclosureTriangleRole, kAXSliderRole, kAXRowRole, "AXLink",
    ]
    /// Most elements visited, so huge windows stay fast.
    private static let nodeLimit = 3_000
    /// Most elements listed.
    private static let elementLimit = 300
    /// Most characters returned.
    private static let characterLimit = 12_000
    /// Longest text-field value shown.
    private static let valueLimit = 80

    /// Name the model calls it by.
    let name = "list_ui_elements"
    /// When to call it and what it returns.
    let description = """
        Lists the controls in an app's front window with ids for click_element, like `[0.3.1] AXButton "Save"`. Ids \
        expire when the window changes, so list again after changes.
        """

    /// Takes an optional app name.
    var parameters: JSONValue {
        Schema.object(["app": Schema.string("Default: frontmost app.")])
    }

    /// Its result carries names and labels others chose (a page, app or file), so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Names the app being inspected.
    func activity(for input: ToolInput) -> String {
        "Looking at the controls in \(input.string("app") ?? "the front app")"
    }

    /// Walks the window depth-first, listing actionable elements by their child-index path.
    func run(_ input: ToolInput) async throws -> String {
        let window = try AccessibilityElement.focusedWindow(of: appOtherThanMacobar(named: input.string("app")))
        var lines: [String] = []
        var characterCount = 0
        var visitedCount = 0
        var pending: [(element: AccessibilityElement, path: [Int])] = window.children.enumerated().map { ($1, [$0]) }.reversed()
        while let (element, path) = pending.popLast(), visitedCount < Self.nodeLimit,
              lines.count < Self.elementLimit, characterCount < Self.characterLimit {
            visitedCount += 1
            if let role = element.role, Self.actionableRoles.contains(role) {
                let line = Self.line(for: element, role: role, path: path)
                lines.append(line)
                characterCount += line.count + 1
            }
            pending.append(contentsOf: element.children.enumerated().map { ($1, path + [$0]) }.reversed())
        }
        guard !lines.isEmpty else { return "Window \"\(window.title ?? "Untitled")\" has no controls macobar can see." }
        let truncation = pending.isEmpty ? "" : "\n… (more controls not listed)"
        return "Window: \(window.title ?? "Untitled")\n" + lines.joined(separator: "\n") + truncation
    }

    /// One listing line: id, role, name, a text field's value, and whether it's disabled.
    private static func line(for element: AccessibilityElement, role: String, path: [Int]) -> String {
        var line = "[\(path.map(String.init).joined(separator: "."))] \(role)"
        if let name = [element.title, element.label].compactMap(\.self).first(where: { !$0.isEmpty }) {
            line += " \"\(name)\""
        }
        if textInputRoles.contains(role), !isSecureTextField(element), let value = element.value, !value.isEmpty {
            line += " value: \"\(value.prefix(valueLimit))\""
        }
        if element.attribute(kAXEnabledAttribute) as Bool? == false {
            line += " (disabled)"
        }
        return line
    }
}

/// Clicks, focuses or selects one element found by `list_ui_elements`.
struct ClickElementTool: Tool {
    /// Actions that count as a click, in order of preference.
    private static let clickActions = [kAXPressAction, kAXConfirmAction, kAXPickAction]

    /// Name the model calls it by.
    let name = "click_element"
    /// When to call it and what it returns.
    let description = """
        Clicks a control by its list_ui_elements id: presses, toggles, selects rows, or focuses a text field (then \
        use type_text).
        """

    /// Takes an optional app and the element id.
    var parameters: JSONValue {
        Schema.object([
            "app": Schema.string("Default: frontmost app."),
            "element_id": Schema.string("Id from list_ui_elements, e.g. \"0.3.1\"."),
        ], required: ["element_id"])
    }

    /// Clicking can change or submit things, so it asks first.
    func risk(for input: ToolInput) -> ToolRisk { .confirmOnce }

    /// Its result carries names and labels others chose (a page, app or file), so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Names the element when it can be found, else just the app.
    func activity(for input: ToolInput) -> String {
        let appName = input.string("app") ?? "the front app"
        guard let app = try? appOtherThanMacobar(named: input.string("app")),
              let element = try? Self.element(at: input.requiredString("element_id"), in: app),
              let elementName = Self.name(of: element)
        else { return "Clicking an element in \(appName)" }
        return "Clicking \"\(elementName)\" in \(app.localizedName ?? appName)"
    }

    /// Re-finds the element and clicks, focuses or selects it.
    func run(_ input: ToolInput) async throws -> String {
        let element = try Self.element(at: input.requiredString("element_id"), in: appOtherThanMacobar(named: input.string("app")))
        let role = element.role ?? "element"
        let description = [role, Self.name(of: element).map { "\"\($0)\"" }].compactMap(\.self).joined(separator: " ")
        if textInputRoles.contains(role) {
            try element.set(kAXFocusedAttribute, to: true as CFBoolean)
            return "Focused \(description); use type_text to type into it."
        }
        var actionNames: CFArray?
        AXUIElementCopyActionNames(element.element, &actionNames)
        let supportedActions = actionNames as? [String] ?? []
        if let action = Self.clickActions.first(where: supportedActions.contains) {
            try element.perform(action)
            return "Clicked \(description)."
        }
        if role == kAXRowRole {
            try element.set(kAXSelectedAttribute, to: true as CFBoolean)
            return "Selected \(description)."
        }
        throw ToolError("\(description) can't be clicked. Its actions: \(supportedActions.joined(separator: ", ")).")
    }

    /// The element at `path` (child indices joined by dots) under `app`'s focused window.
    private static func element(at path: String, in app: NSRunningApplication) throws -> AccessibilityElement {
        var element = try AccessibilityElement.focusedWindow(of: app)
        for component in path.split(separator: ".") {
            let children = element.children
            guard let index = Int(component), children.indices.contains(index) else {
                throw ToolError("Element \(path) no longer exists. Call list_ui_elements again for fresh ids.")
            }
            element = children[index]
        }
        return element
    }

    /// The element's title or description, when it has one.
    private static func name(of element: AccessibilityElement) -> String? {
        [element.title, element.label].compactMap(\.self).first { !$0.isEmpty }
    }
}

/// Chooses an item from an app's menu bar.
struct ClickMenuItemTool: Tool {
    /// Name the model calls it by.
    let name = "click_menu_item"
    /// When to call it and what it returns.
    let description = """
        Chooses a menu bar command by path, e.g. ["File", "Export…"]; often the most reliable way to run a command. \
        Errors list the available items.
        """

    /// Takes an optional app and the menu path.
    var parameters: JSONValue {
        Schema.object([
            "app": Schema.string("Default: frontmost app."),
            "path": Schema.strings("Menu titles from the menu bar down to the item."),
        ], required: ["path"])
    }

    /// Menu commands can change or delete things, so it asks first.
    func risk(for input: ToolInput) -> ToolRisk { .confirmOnce }

    /// Its errors list menu items, which in browsers' Window, History and Bookmarks menus are page titles others chose.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Names the menu path and app.
    func activity(for input: ToolInput) -> String {
        "Choosing \(input.strings("path").joined(separator: " › ")) in \(input.string("app") ?? "the front app")"
    }

    /// Walks the menu bar down the path and presses the last item.
    func run(_ input: ToolInput) async throws -> String {
        let titles = input.strings("path")
        guard let finalTitle = titles.last else { throw ToolError("Pass the menu path, e.g. [\"File\", \"Save\"].") }
        try AccessibilityElement.requirePermission()
        let app = try appOtherThanMacobar(named: input.string("app"))
        guard var menu = AccessibilityElement.application(app).elementAttribute(kAXMenuBarAttribute) else {
            throw ToolError("\(app.localizedName ?? "That app") has no menu bar.")
        }
        for title in titles.dropLast() {
            let item = try Self.item(titled: title, in: menu)
            guard let submenu = item.children.first(where: { $0.role == kAXMenuRole }) else {
                throw ToolError("\"\(title)\" has no submenu.")
            }
            menu = submenu
        }
        let item = try Self.item(titled: finalTitle, in: menu)
        guard item.attribute(kAXEnabledAttribute) as Bool? != false else {
            throw ToolError("\"\(finalTitle)\" is disabled right now.")
        }
        try item.perform(kAXPressAction)
        return "Chose \(titles.joined(separator: " › ")) in \(app.localizedName ?? "the app")."
    }

    /// The item in `menu` titled `title`, or an error listing the titles that are there.
    private static func item(titled title: String, in menu: AccessibilityElement) throws -> AccessibilityElement {
        let items = menu.children
        if let match = items.first(where: { $0.title.map(comparable) == comparable(title) }) {
            return match
        }
        let available = items.compactMap(\.title).filter { !$0.isEmpty }
        throw ToolError("No menu item \"\(title)\". Available here: \(available.joined(separator: ", ")).")
    }

    /// `title` reduced for loose matching: lowercased, trimmed, without ellipses.
    private static func comparable(_ title: String) -> String {
        title.replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespaces).lowercased()
    }
}

/// Types text into an app's focused field by sending it keystrokes directly.
struct TypeTextTool: Tool {
    /// Most UTF-16 units one keyboard event can carry.
    private static let chunkLimit = 20
    /// Pause between events so the app keeps up.
    private static let chunkDelay = Duration.milliseconds(10)

    /// Name the model calls it by.
    let name = "type_text"
    /// When to call it and what it returns.
    let description = """
        Types text as keystrokes into an app's focused field; newlines press Return. Focus the field first \
        (click_element or click_mark) if needed.
        """

    /// Takes the text and an optional app.
    var parameters: JSONValue {
        Schema.object([
            "text": Schema.string("Exact text to type."),
            "app": Schema.string("Default: frontmost app."),
        ], required: ["text"])
    }

    /// Typing changes the user's documents, so it asks first; typing into a password field asks every time.
    func risk(for input: ToolInput) -> ToolRisk {
        Self.focusesPasswordField(input) ? .confirmEveryTime : .confirmOnce
    }

    /// Names the target app and shows what will be typed, so the user approves the actual text; a password is never shown.
    func activity(for input: ToolInput) -> String {
        let appName = input.string("app") ?? "the front app"
        let text = input.rawString("text") ?? ""
        guard !Self.focusesPasswordField(input) else { return "Typing \(text.count) characters into a password field in \(appName)" }
        return "Typing \(approvalPreview(of: text)) into \(appName)"
    }

    /// Whether the field that would receive the keystrokes is a password field.
    private static func focusesPasswordField(_ input: ToolInput) -> Bool {
        guard let app = try? RunningApps.find(input.string("app")),
              let focused = AccessibilityElement.application(app).elementAttribute(kAXFocusedUIElementAttribute)
        else { return false }
        return isSecureTextField(focused)
    }

    /// Sends the text in small chunks, pressing Return for newlines.
    func run(_ input: ToolInput) async throws -> String {
        guard let text = input.rawString("text"), !text.isEmpty else { throw ToolError("Missing required argument \"text\".") }
        let app = try keystrokeTarget(input.string("app"))
        for chunk in Self.chunks(of: text) {
            if chunk == "\n" {
                try postKeystroke(to: app.processIdentifier, keyCode: CGKeyCode(kVK_Return))
            } else {
                try postKeystroke(to: app.processIdentifier, text: Array(chunk.utf16))
            }
            try await Task.sleep(for: Self.chunkDelay)
        }
        return "Typed \(text.count) characters into \(app.localizedName ?? "the app")."
    }

    /// `text` split into pieces of at most `chunkLimit` UTF-16 units, with each newline as its own "\n" piece.
    private static func chunks(of text: String) -> [String] {
        var chunks: [String] = []
        for character in text {
            if character.isNewline {
                chunks.append("\n")
            } else if let last = chunks.last, last != "\n", last.utf16.count + character.utf16.count <= chunkLimit {
                chunks[chunks.count - 1].append(character)
            } else {
                chunks.append(String(character))
            }
        }
        return chunks
    }
}

/// Presses a key or keyboard shortcut in an app.
struct PressKeysTool: Tool {
    /// Modifier names and the event flags they set.
    private static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand, "shift": .maskShift, "option": .maskAlternate,
        "alt": .maskAlternate, "ctrl": .maskControl, "control": .maskControl, "fn": .maskSecondaryFn,
    ]
    /// Key names and their virtual key codes.
    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab, "space": kVK_Space,
        "delete": kVK_Delete, "backspace": kVK_Delete, "forwarddelete": kVK_ForwardDelete,
        "escape": kVK_Escape, "esc": kVK_Escape,
        "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
        "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
        "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
        ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
        "/": kVK_ANSI_Slash, "`": kVK_ANSI_Grave, "\\": kVK_ANSI_Backslash,
    ]

    /// Name the model calls it by.
    let name = "press_keys"
    /// When to call it and what it returns.
    let description = """
        Presses a key or shortcut, e.g. "cmd+shift+s", "esc", "down". Use type_text for text, and click_menu_item \
        when a menu command exists.
        """

    /// Takes the shortcut and an optional app.
    var parameters: JSONValue {
        Schema.object([
            "keys": Schema.string("Key with \"+\"-joined modifiers: cmd, shift, option, ctrl, fn."),
            "app": Schema.string("Default: frontmost app."),
        ], required: ["keys"])
    }

    /// Shortcuts can change or delete things, so it asks first.
    func risk(for input: ToolInput) -> ToolRisk { .confirmOnce }

    /// Names the shortcut and app.
    func activity(for input: ToolInput) -> String {
        "Pressing \(input.string("keys") ?? "keys") in \(input.string("app") ?? "the front app")"
    }

    /// Parses the shortcut and sends it to the app.
    func run(_ input: ToolInput) async throws -> String {
        let keys = try input.requiredString("keys")
        let parts = keys.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyName = parts.last, let keyCode = Self.keyCodes[keyName] else {
            throw ToolError("Unknown key in \"\(keys)\". Use a letter, digit, punctuation, or a name like return, tab, space, esc, delete, up, home, pagedown, f5.")
        }
        var flags: CGEventFlags = []
        for modifierName in parts.dropLast() {
            guard let modifier = Self.modifiers[modifierName] else {
                throw ToolError("Unknown modifier \"\(modifierName)\". Use cmd, shift, option, ctrl or fn.")
            }
            flags.insert(modifier)
        }
        let app = try keystrokeTarget(input.string("app"))
        try postKeystroke(to: app.processIdentifier, keyCode: CGKeyCode(keyCode), flags: flags)
        return "Pressed \(keys) in \(app.localizedName ?? "the app")."
    }
}

/// Roles that take typed text, which clicking focuses.
private let textInputRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]

/// The app named `appName` (or the frontmost), refusing macobar itself and checking permission to send it keystrokes.
private func keystrokeTarget(_ appName: String?) throws -> NSRunningApplication {
    try AccessibilityElement.requirePermission()
    return try appOtherThanMacobar(named: appName)
}

/// The app named `appName` (or the frontmost), refusing macobar itself, so Macie never reads or presses her own windows (approvals, settings, the sharing token).
func appOtherThanMacobar(named appName: String?) throws -> NSRunningApplication {
    let app = try RunningApps.find(appName)
    guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
        throw ToolError("That's macobar itself, which Macie never reads or controls. Name the app to use.")
    }
    return app
}

/// Whether `element` is a password field, whose value is never read out or shown.
func isSecureTextField(_ element: AccessibilityElement) -> Bool {
    element.attribute(kAXSubroleAttribute) as String? == kAXSecureTextFieldSubrole
}

/// `text` on one line with every newline shown (even a trailing one that presses Return), quoted and cut to a readable length with its full length named, without invisible format characters (direction overrides, zero-width spaces) that could reorder it or hide text past the cut, for approval prompts.
func approvalPreview(of text: String) -> String {
    let previewLimit = 80
    let line = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).joined(separator: " ⏎ ")
    let visible = String(line.unicodeScalars.filter { !$0.properties.isBidiControl && $0.properties.generalCategory != .format })
    guard visible.count > previewLimit else { return "“" + visible + "”" }
    return "“" + visible.prefix(previewLimit - 1) + "…” (\(text.count) characters)"
}

/// Sends one key press (down, then up) straight to `pid`, typing `text` in place of the key's own character when given.
private func postKeystroke(to pid: pid_t, keyCode: CGKeyCode = 0, flags: CGEventFlags = [], text: [UniChar] = []) throws {
    for isKeyDown in [true, false] {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: isKeyDown) else {
            throw ToolError("Couldn't create a keyboard event.")
        }
        event.flags = flags
        if !text.isEmpty {
            event.keyboardSetUnicodeString(stringLength: text.count, unicodeString: text)
        }
        event.postToPid(pid)
    }
}
