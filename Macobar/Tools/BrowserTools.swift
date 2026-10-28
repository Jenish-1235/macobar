import AppKit

/// Reads the page in the browser's front tab: its text plus numbered links, buttons and form fields.
struct ReadPageTool: Tool {
    /// Most characters of page text returned.
    private static let textLimit = 15_000
    /// Most controls listed.
    private static let controlLimit = 200

    /// Name the model calls it by.
    let name = "read_page"
    /// When to call it and what it returns.
    let description = """
        Reads the browser's front tab: title, URL, text and numbered links, buttons and fields. For the page the user \
        is on, prefer it over read_window_text and fetch_web_page (it sees signed-in content). The numbers feed \
        click_on_page and fill_on_page; read again after the page changes.
        """

    /// Takes no arguments.
    var parameters: JSONValue { Schema.object() }

    /// Its result carries outside text the model will read, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Describes the read.
    func activity(for input: ToolInput) -> String {
        "Reading the page in the browser"
    }

    /// Runs the read script in the front tab and lays out its text and controls.
    func run(_ input: ToolInput) async throws -> String {
        let tab = try FrontTab.current()
        let page = try await tab.evaluate(
            PageScript.readPage(textLimit: Self.textLimit, controlLimit: Self.controlLimit), as: PageContents.self)
        var sections = ["Browser: \(tab.appName)\nTitle: \(page.title)\nURL: \(page.url)"]
        let text = page.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let truncation = page.textLength > Self.textLimit
                ? "\n[Truncated: showing the first \(Self.textLimit) of \(page.textLength) characters.]" : ""
            sections.append(text + truncation)
        }
        if !page.controls.isEmpty {
            let lines = page.controls.enumerated().map { "[\($0.offset + 1)] \($0.element)" }
            let unlisted = page.controlCount - page.controls.count
            let more = unlisted > 0 ? "\n… \(unlisted) more not listed." : ""
            sections.append("Links and fields (pass the number to click_on_page or fill_on_page):\n" + lines.joined(separator: "\n") + more)
        }
        return sections.joined(separator: "\n\n")
    }
}

/// Clicks a link, button or other control on the page in the browser's front tab.
struct ClickOnPageTool: Tool {
    /// Name the model calls it by.
    let name = "click_on_page"
    /// When to call it and what it returns.
    let description = """
        Clicks a link, button or control in the browser's front tab. Call read_page before to find it and after to \
        see what changed.
        """

    /// Takes the control's number or its visible text.
    var parameters: JSONValue {
        Schema.object([
            "index": Schema.integer("Number from read_page (preferred)."),
            "text": Schema.string("Visible label, if no index."),
        ])
    }

    /// Clicking can submit forms or buy things, so it asks first.
    func risk(for input: ToolInput) -> ToolRisk {
        .confirmOnce
    }

    /// Its result names the control in the page's own words, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Names the control being clicked.
    func activity(for input: ToolInput) -> String {
        if let index = input.integer("index") { return "Clicking item \(index) on the page" }
        return "Clicking \"\(input.string("text") ?? "a control")\" on the page"
    }

    /// Runs the click script in the front tab.
    func run(_ input: ToolInput) async throws -> String {
        let script: String
        if let index = input.integer("index") {
            guard index >= 1 else { throw ToolError("index starts at 1. Use a number from read_page.") }
            script = PageScript.click(index: index)
        } else if let text = input.string("text") {
            script = PageScript.click(text: text)
        } else {
            throw ToolError("Pass index (a number from read_page) or text (the label of the link or button).")
        }
        let tab = try FrontTab.current()
        let clicked = try await tab.evaluate(script, as: String.self)
        return "Clicked \(clicked) in \(tab.appName)."
    }
}

/// Fills a text field, text area, menu or checkbox on the page in the browser's front tab.
struct FillOnPageTool: Tool {
    /// Name the model calls it by.
    let name = "fill_on_page"
    /// When to call it and what it returns.
    let description = """
        Sets a form field in the browser's front tab: text, a menu option, or a checkbox/radio. Works with \
        React-style forms. Doesn't submit: click the submit button with click_on_page.
        """

    /// Takes the field's number and the value.
    var parameters: JSONValue {
        Schema.object([
            "index": Schema.integer("Field number from read_page."),
            "value": Schema.string("Text, menu option value or label, or \"true\"/\"false\"."),
        ], required: ["index", "value"])
    }

    /// Filling in forms changes what the page will send, so it asks first.
    func risk(for input: ToolInput) -> ToolRisk {
        .confirmOnce
    }

    /// Its result names the field in the page's own words, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Shows the value, shortened to one line, and the field.
    func activity(for input: ToolInput) -> String {
        let value = (input.rawString("value") ?? "").split(whereSeparator: \.isNewline).joined(separator: " ")
        let field = input.integer("index").map { "field \($0)" } ?? "a field"
        return "Setting \(field) to \"\(value.count > 40 ? value.prefix(39) + "…" : value)\" on the page"
    }

    /// Runs the fill script in the front tab.
    func run(_ input: ToolInput) async throws -> String {
        guard let index = input.integer("index"), index >= 1 else {
            throw ToolError("Pass index, the field's number from read_page (it starts at 1).")
        }
        guard let value = input.rawString("value") else { throw ToolError("Missing required argument \"value\".") }
        let field = try await FrontTab.current().evaluate(PageScript.fill(index: index, value: value), as: String.self)
        return "Set \(field)."
    }
}

/// Runs JavaScript the model writes in the page in the browser's front tab.
struct RunPageScriptTool: Tool {
    /// Most characters of the result returned.
    private static let resultLimit = 15_000

    /// Name the model calls it by.
    let name = "run_page_script"
    /// When to call it and what it returns.
    let description = """
        Runs JavaScript in the browser's front tab; a last resort when read_page, click_on_page and fill_on_page can't \
        (e.g. scrolling). Returns the last expression's value as JSON: no top-level return, promises aren't awaited. \
        The user approves every run.
        """

    /// The script source.
    var parameters: JSONValue {
        Schema.object(["script": Schema.string("JavaScript to run.")], required: ["script"])
    }

    /// Arbitrary scripts can do anything the signed-in user can, so they ask every time.
    func risk(for input: ToolInput) -> ToolRisk {
        .confirmEveryTime
    }

    /// Its result carries outside text the model will read, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    /// Describes the run.
    func activity(for input: ToolInput) -> String {
        "Running JavaScript in the page"
    }

    /// Runs the script in the front tab and returns its JSON result, cut to `resultLimit` characters.
    func run(_ input: ToolInput) async throws -> String {
        let script = try input.requiredString("script")
        let result = try await FrontTab.current().evaluate(PageScript.evaluate(script), as: String.self)
        guard result.count > Self.resultLimit else { return result }
        return "\(result.prefix(Self.resultLimit))\n[Truncated: showing the first \(Self.resultLimit) of \(result.count) characters.]"
    }
}

/// What the read script reports about the page.
private struct PageContents: Decodable {
    /// The document title.
    let title: String
    /// The page's address.
    let url: String
    /// The start of the visible text.
    let text: String
    /// Length of the whole visible text, in UTF-16 units.
    let textLength: Int
    /// The first controls, each described on one line, in index order.
    let controls: [String]
    /// How many controls the page has in all.
    let controlCount: Int
}

/// What every page script reports: its value, or why it failed.
private struct PageReply<Value: Decodable>: Decodable {
    /// The script's result.
    let value: Value?
    /// The message of the error the script threw.
    let error: String?
}

/// The front tab of the frontmost supported browser, where page scripts run.
private struct FrontTab {
    /// Chromium browsers by bundle identifier, with the names their AppleScript dictionaries answer to.
    private static let chromiumBrowsers = [
        "com.google.Chrome": "Google Chrome",
        "company.thebrowser.Browser": "Arc",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.brave.Browser": "Brave Browser",
        "org.chromium.Chromium": "Chromium",
    ]

    /// The browser's name, for messages.
    let appName: String
    /// AppleScript whose `on run argv` runs item 1 as JavaScript in the front tab and returns the result.
    let script: String
    /// How the user lets this browser run JavaScript from Apple Events.
    let enablingSteps: String

    /// The frontmost running browser that can run JavaScript in its front tab.
    static func current() throws -> FrontTab {
        for app in RunningApps.regular {
            let appName = app.localizedName ?? "The browser"
            if app.bundleIdentifier == "com.apple.Safari" {
                return FrontTab(
                    appName: appName,
                    script: """
                        on run argv
                            tell application "Safari" to do JavaScript (item 1 of argv) in front document
                        end run
                        """,
                    enablingSteps: """
                        in Safari, choose Settings → Advanced and turn on "Show features for web developers", \
                        then choose Develop → Allow JavaScript from Apple Events.
                        """
                )
            }
            if let dictionaryName = app.bundleIdentifier.flatMap({ chromiumBrowsers[$0] }) {
                return FrontTab(
                    appName: appName,
                    script: """
                        on run argv
                            tell application "\(dictionaryName)" to tell active tab of front window to execute javascript (item 1 of argv)
                        end run
                        """,
                    enablingSteps: "in \(appName), choose View → Developer → Allow JavaScript from Apple Events."
                )
            }
        }
        throw ToolError("No supported browser is running. Open the page in Safari, Chrome, Arc, Edge, Brave or Chromium first.")
    }

    /// Runs `javascript`, built by `PageScript`, and decodes the value it reports.
    func evaluate<Value: Decodable>(_ javascript: String, as type: Value.Type) async throws -> Value {
        let output: String
        do {
            output = try await AppleScript.run(script, arguments: [javascript])
        } catch {
            throw explaining(error)
        }
        guard let reply = try? JSONDecoder().decode(PageReply<Value>.self, from: Data(output.utf8)) else {
            throw ToolError("\(appName) didn't run the script; the page may still be loading. Try again in a moment.")
        }
        if let error = reply.error { throw ToolError(error) }
        guard let value = reply.value else { throw ToolError("The script in \(appName) returned nothing.") }
        return value
    }

    /// `error` from `osascript` rewritten to say how the user can fix it.
    private func explaining(_ error: Error) -> ToolError {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("JavaScript from Apple Events")
            || message.localizedCaseInsensitiveContains("JavaScript through AppleScript") {
            return ToolError("\(appName) doesn't allow JavaScript from Apple Events yet. Ask the user to turn it on: \(enablingSteps)")
        }
        if message.contains("-1743") {
            return ToolError("""
                macobar isn't allowed to control \(appName). The user can allow it in System Settings → Privacy & Security \
                → Automation → macobar.
                """)
        }
        return ToolError("Couldn't run JavaScript in \(appName)'s front tab: \(message) If it has no window open, open the page first.")
    }
}

/// JavaScript the page tools run in the front tab, built from fixed source with arguments injected only as JSON literals.
enum PageScript {
    /// Numbers the page's visible controls (marking each with `data-macie-index`) and reports the title, URL, text and controls.
    static func readPage(textLimit: Int, controlLimit: Int) -> String {
        wrapping(#"""
            document.querySelectorAll('[data-macie-index]').forEach((element) => element.removeAttribute('data-macie-index'));
            const found = controls();
            found.forEach((element, position) => element.setAttribute('data-macie-index', String(position + 1)));
            const text = document.body ? document.body.innerText : '';
            return {
              title: document.title,
              url: location.href,
              text: text.slice(0, \#(literal(textLimit))),
              textLength: text.length,
              controls: found.slice(0, \#(literal(controlLimit))).map((element) => describe(element)),
              controlCount: found.length,
            };
            """#)
    }

    /// Clicks the control numbered `index` by `readPage` and reports what it was.
    static func click(index: Int) -> String {
        clicking("controlAt(\(literal(index)))")
    }

    /// Clicks the control labelled `text` (exact match first, then containing it) and reports what it was.
    static func click(text: String) -> String {
        clicking("controlNamed(\(literal(text)))")
    }

    /// Sets the control numbered `index` to `value` with native setters and input/change events; reports its new state.
    static func fill(index: Int, value: String) -> String {
        wrapping(#"""
            const index = \#(literal(index));
            let value = \#(literal(value));
            const element = controlAt(index);
            const kind = kindOf(element);
            element.scrollIntoView({ block: 'center' });
            element.focus?.();
            if (kind === 'checkbox' || kind === 'radio') {
              const wanted = ['true', 'yes', 'on', '1', 'checked'].includes(value.trim().toLowerCase());
              if (isChecked(element) !== wanted) press(element);
              return describe(element);
            }
            if (!isField(kind)) throw new Error('Control ' + index + ' is a ' + kind + ', not a field. Use click_on_page for it.');
            if (element.isContentEditable) {
              document.execCommand('selectAll');
              if (!document.execCommand('insertText', false, value)) element.textContent = value;
              return describe(element);
            }
            if (kind === 'menu') {
              const options = [...element.options];
              const option = options.find((choice) => choice.value === value)
                || options.find((choice) => squeeze(choice.text).toLowerCase() === squeeze(value).toLowerCase());
              if (!option) throw new Error('Menu ' + index + ' has no option "' + value + '". Its options: ' + options.map((choice) => squeeze(choice.text)).join(', ') + '.');
              value = option.value;
            }
            const type = { select: HTMLSelectElement, textarea: HTMLTextAreaElement }[element.localName] ?? HTMLInputElement;
            Object.getOwnPropertyDescriptor(type.prototype, 'value').set.call(element, value);
            element.dispatchEvent(new Event('input', { bubbles: true }));
            element.dispatchEvent(new Event('change', { bubbles: true }));
            return describe(element);
            """#)
    }

    /// Runs `script` in the page's global scope and reports its completion value as JSON text.
    static func evaluate(_ script: String) -> String {
        wrapping(#"""
            const result = (0, eval)(\#(literal(script)));
            return result === undefined ? 'undefined' : JSON.stringify(result) ?? String(result);
            """#)
    }

    /// `value` as a JSON literal, safe to place in JavaScript source whatever characters it holds.
    static func literal(_ value: some Encodable) -> String {
        (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }

    /// A script that scrolls to, presses and describes the control `target` evaluates to.
    private static func clicking(_ target: String) -> String {
        wrapping("""
            const element = \(target);
            const description = describe(element);
            press(element);
            return description;
            """)
    }

    /// `body` inside a function with the shared helpers, its result or error reported as `{"value"}` or `{"error"}` JSON text.
    private static func wrapping(_ body: String) -> String {
        """
        (() => {
        \(helpers)
        try {
          return JSON.stringify({ value: (() => {
        \(body)
          })() });
        } catch (error) {
          return JSON.stringify({ error: String(error?.message ?? error) });
        }
        })()
        """
    }

    /// Functions every page script shares for finding, describing and pressing controls.
    private static let helpers = #"""
        const controlSelector = 'a[href], button, input:not([type="hidden"]), select, textarea, [role="button"], [role="link"], '
          + '[role="checkbox"], [role="tab"], [role="menuitem"], [contenteditable=""], [contenteditable="true"]';
        const squeeze = (text) => (text || '').replace(/\s+/g, ' ').trim();
        const controls = () => [...document.querySelectorAll(controlSelector)].filter((element) => element.getClientRects().length > 0);
        const kindOf = (element) => {
          const tag = element.localName;
          if (tag === 'a') return 'link';
          if (tag === 'button') return 'button';
          if (tag === 'select') return 'menu';
          if (tag === 'textarea') return 'text area';
          if (tag === 'input') {
            const type = (element.getAttribute('type') || 'text').toLowerCase();
            if (['submit', 'button', 'reset', 'image'].includes(type)) return 'button';
            return type === 'checkbox' || type === 'radio' ? type : type + ' field';
          }
          if (element.isContentEditable) return 'text area';
          return element.getAttribute('role') || 'control';
        };
        const isField = (kind) => kind === 'menu' || kind === 'text area' || kind.endsWith(' field');
        const isChecked = (element) => element.checked ?? element.getAttribute('aria-checked') === 'true';
        const labelOf = (element) => {
          const kind = kindOf(element);
          const image = element.querySelector('img[alt]');
          const candidates = [
            element.getAttribute('aria-label'),
            element.labels?.length ? element.labels[0].innerText : '',
            isField(kind) ? '' : element.innerText,
            element.localName === 'input' && kind === 'button' ? element.value : '',
            element.getAttribute('placeholder'),
            element.getAttribute('title'),
            image ? image.getAttribute('alt') : '',
            element.getAttribute('name'),
          ];
          return squeeze(candidates.find((candidate) => squeeze(candidate)));
        };
        const detailOf = (element, kind) => {
          if (kind === 'link') return element.href ? '→ ' + String(element.href).slice(0, 120) : '';
          if (kind === 'checkbox' || kind === 'radio') return isChecked(element) ? '(checked)' : '(unchecked)';
          if (kind === 'menu') return element.selectedIndex >= 0 ? '= "' + squeeze(element.options[element.selectedIndex].text) + '"' : '';
          if (kind === 'password field' || !isField(kind)) return '';
          const value = squeeze(element.isContentEditable ? element.innerText : element.value);
          return value ? '= "' + value.slice(0, 80) + '"' : '';
        };
        const describe = (element) => {
          const kind = kindOf(element);
          const label = labelOf(element).slice(0, 80);
          const disabled = element.disabled || element.getAttribute('aria-disabled') === 'true';
          return [kind, label && '"' + label + '"', detailOf(element, kind), disabled && '(disabled)'].filter(Boolean).join(' ');
        };
        const controlAt = (index) => {
          const marked = [...document.querySelectorAll('[data-macie-index]')];
          const element = marked.length
            ? marked.find((candidate) => candidate.getAttribute('data-macie-index') === String(index))
            : controls()[index - 1];
          if (!element) throw new Error('There is no control ' + index + ' on this page. Call read_page again for the current numbers.');
          return element;
        };
        const controlNamed = (text) => {
          const wanted = squeeze(text).toLowerCase();
          const labelled = controls().map((element) => [element, labelOf(element).toLowerCase()]);
          const match = labelled.find(([, label]) => label === wanted) || labelled.find(([, label]) => label.includes(wanted));
          if (!match) throw new Error('Nothing on this page is labelled "' + text + '". Call read_page to see what can be clicked.');
          return match[0];
        };
        const press = (element) => {
          element.scrollIntoView({ block: 'center', inline: 'center' });
          element.focus?.();
          for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup']) {
            const Kind = type.startsWith('pointer') ? PointerEvent : MouseEvent;
            element.dispatchEvent(new Kind(type, { bubbles: true, cancelable: true, view: window }));
          }
          element.click();
        };
        """#
}
