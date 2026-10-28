import AppKit

/// Opens a URL in the app that handles it.
struct OpenURLTool: Tool {
    /// Schemes that open without asking: web pages, new emails and System Settings panes.
    private static let safeSchemes: Set<String> = ["http", "https", "mailto", "x-apple.systempreferences"]

    let name = "open_url"
    let description = """
        Opens a URL in its default app. Call it when the user wants to see a site; for a web search open \
        https://www.google.com/search?q=… ; for a Settings pane e.g. \
        x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility. To read a page yourself use \
        fetch_web_page.
        """
    var parameters: JSONValue {
        Schema.object([
            "url": Schema.string("Full URL with scheme."),
        ], required: ["url"])
    }

    /// Web, mail and Settings links open freely; any other scheme (files, apps' own links) can run or trigger something, so it asks every time.
    func risk(for input: ToolInput) -> ToolRisk {
        let scheme = input.string("url").flatMap(URL.init(string:))?.scheme?.lowercased()
        return scheme.map(Self.safeSchemes.contains) == true ? .none : .confirmEveryTime
    }

    func activity(for input: ToolInput) -> String {
        "Opening \(input.string("url") ?? "a link")"
    }

    func run(_ input: ToolInput) async throws -> String {
        let text = try input.requiredString("url")
        guard let url = URL(string: text), url.scheme != nil else {
            throw ToolError("\"\(text)\" isn't a full URL. Include the scheme, e.g. https://.")
        }
        guard NSWorkspace.shared.open(url) else { throw ToolError("No app could open \(text).") }
        return "Opened \(text)."
    }
}

/// Downloads a web page and returns its readable text.
struct FetchWebPageTool: Tool {
    /// Most characters returned.
    private static let characterLimit = 20_000
    /// Most bytes downloaded; the rest of a bigger page is ignored.
    private static let byteLimit = 5_000_000
    /// Most redirects followed, each checked like the first address.
    private static let redirectLimit = 5
    /// A Safari User-Agent, so sites serve their normal pages.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    /// A session with no cookies, cache or saved logins, so pages are fetched anonymously.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    let name = "fetch_web_page"
    let description = """
        Downloads a public web page's title and text (up to 20000 characters), for page content or current info; to \
        search, fetch https://html.duckduckgo.com/html/?q=… then the best result. Can't reach this Mac or the LAN.
        """
    var parameters: JSONValue {
        Schema.object([
            "url": Schema.string("http or https URL."),
        ], required: ["url"])
    }

    /// Its result carries outside text the model will read, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    func activity(for input: ToolInput) -> String {
        "Reading \(input.string("url").flatMap(URL.init(string:))?.host() ?? "a web page")"
    }

    func run(_ input: ToolInput) async throws -> String {
        let text = try input.requiredString("url")
        var address = try Self.webURL(text)
        for _ in 0...Self.redirectLimit {
            try await Self.requirePublic(address)
            let (data, response) = try await Self.download(address)
            if let redirect = Self.redirectTarget(of: response, from: address) {
                address = try Self.webURL(redirect.absoluteString)
                continue
            }
            return try Self.readable(data, response: response, address: address)
        }
        throw ToolError("\(text) redirected more than \(Self.redirectLimit) times.")
    }

    /// `text` as an http or https URL, or an error saying it isn't one.
    private static func webURL(_ text: String) throws -> URL {
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased()), url.host() != nil else {
            throw ToolError("\"\(text)\" isn't an http or https URL.")
        }
        return url
    }

    /// Throws unless `url`'s host is on the public internet, so the model can't be steered into reading this Mac's or the network's private servers.
    private static func requirePublic(_ url: URL) async throws {
        guard let host = url.host(), await PublicNetworkAddress.isPublicHost(host) else {
            throw ToolError("""
                \(url.absoluteString) isn't a public internet address (it's this Mac, the local network, or doesn't exist), \
                so it can't be fetched. Use open_url to show it in the browser instead.
                """)
        }
    }

    /// The first `byteLimit` bytes at `url` and the response, without following redirects.
    private static func download(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: RedirectRefuser())
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count >= byteLimit { break }
            }
            return (data, response)
        } catch {
            throw ToolError("Couldn't load \(url.absoluteString): \(error.localizedDescription)")
        }
    }

    /// Where a redirect `response` points, resolved against `address`; nil when it isn't a redirect.
    private static func redirectTarget(of response: URLResponse, from address: URL) -> URL? {
        guard let response = response as? HTTPURLResponse, (300..<400).contains(response.statusCode),
              let location = response.value(forHTTPHeaderField: "Location") else { return nil }
        return URL(string: location, relativeTo: address)?.absoluteURL
    }

    /// The page in `data` as a title, address and readable text, or an error for failures and non-text content.
    private static func readable(_ data: Data, response: URLResponse, address: URL) throws -> String {
        let text = address.absoluteString
        if let status = (response as? HTTPURLResponse)?.statusCode, status >= 300 {
            throw ToolError("\(text) returned HTTP \(status).")
        }
        let mimeType = response.mimeType ?? "text/html"
        guard mimeType.hasPrefix("text/") || mimeType.contains("json") || mimeType.contains("xml") else {
            throw ToolError("\(text) is \(mimeType), not a web page. Use open_url to open it instead.")
        }
        let body = String(decoding: data, as: UTF8.self)
        let page = mimeType.contains("html") ? ReadablePage(html: body) : ReadablePage(title: "", text: body)
        let header = page.title.isEmpty ? "URL: \(text)" : "Title: \(page.title)\nURL: \(text)"
        guard page.text.count > characterLimit else { return "\(header)\n\n\(page.text)" }
        return "\(header)\n\n\(page.text.prefix(characterLimit))\n[Truncated: showing the first \(characterLimit) of \(page.text.count) characters.]"
    }
}

/// A web page reduced to its title and plain text.
struct ReadablePage {
    /// The page's `<title>`, or empty.
    let title: String
    /// The visible text, with tags and boilerplate removed.
    let text: String

    /// Wraps an already plain `title` and `text`.
    init(title: String, text: String) {
        self.title = title
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Elements whose contents are never readable text.
    private static let skippedElements: Set = ["script", "style", "nav", "svg", "noscript", "head"]
    /// Tags that end a line of text.
    private static let lineBreakTags: Set = ["br", "/p", "/div", "/li", "/tr", "/h1", "/h2", "/h3", "/h4", "/h5", "/h6"]

    /// Extracts the title and readable text from `html` in one forward pass, so hostile markup (thousands of unclosed tags) can't make it slow, as backtracking patterns could.
    init(html: String) {
        let bytes = Array(html.utf8)
        self.init(title: Self.decodingEntities(Self.title(in: bytes)).collapsingWhitespace,
                  text: Self.decodingEntities(Self.visibleText(in: bytes)).collapsingLines)
    }

    /// The text between the first `<title …>` and `</title>` in `bytes`, or empty.
    private static func title(in bytes: [UInt8]) -> String {
        guard let start = firstIndex(of: "<title", in: bytes, from: 0),
              let openEnd = bytes[start...].firstIndex(of: UInt8(ascii: ">")),
              let end = firstIndex(of: "</title>", in: bytes, from: openEnd + 1) else { return "" }
        return String(decoding: bytes[(openEnd + 1)..<end], as: UTF8.self)
    }

    /// `bytes` without comments, tags, or the contents of `skippedElements`, with `lineBreakTags` turned into line breaks.
    private static func visibleText(in bytes: [UInt8]) -> String {
        var text: [UInt8] = []
        var index = 0
        while index < bytes.count {
            guard bytes[index] == UInt8(ascii: "<") else {
                text.append(bytes[index])
                index += 1
                continue
            }
            if matches("<!--", in: bytes, at: index) {
                // An unclosed comment runs to the end of the page.
                guard let end = firstIndex(of: "-->", in: bytes, from: index + 4) else { break }
                index = end + 3
                continue
            }
            guard let tagEnd = bytes[index...].firstIndex(of: UInt8(ascii: ">")) else {
                text.append(contentsOf: bytes[index...])
                break
            }
            let name = tagName(bytes[(index + 1)..<tagEnd])
            index = tagEnd + 1
            if lineBreakTags.contains(name) { text.append(UInt8(ascii: "\n")) }
            if skippedElements.contains(name) {
                // An unclosed script or style runs to the end of the page.
                guard let close = firstIndex(of: "</" + name, in: bytes, from: index),
                      let closeEnd = bytes[close...].firstIndex(of: UInt8(ascii: ">")) else { break }
                index = closeEnd + 1
            }
        }
        return String(decoding: text, as: UTF8.self)
    }

    /// The lowercased name of the tag whose inside (between `<` and `>`) is `inside`, with a leading "/" for a closing tag, e.g. "br" or "/p".
    private static func tagName(_ inside: ArraySlice<UInt8>) -> String {
        let isClosing = inside.first == UInt8(ascii: "/")
        let name = inside.dropFirst(isClosing ? 1 : 0).prefix { byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(lowercased(byte))
        }
        return (isClosing ? "/" : "") + String(decoding: name.map(lowercased), as: UTF8.self)
    }

    /// Where the ASCII `pattern` first appears in `bytes` at or after `start`, ignoring letter case; nil when it doesn't.
    private static func firstIndex(of pattern: String, in bytes: [UInt8], from start: Int) -> Int? {
        var index = start
        while index + pattern.utf8.count <= bytes.count {
            if matches(pattern, in: bytes, at: index) { return index }
            index += 1
        }
        return nil
    }

    /// Whether the ASCII `pattern` appears in `bytes` at `index`, ignoring letter case.
    private static func matches(_ pattern: String, in bytes: [UInt8], at index: Int) -> Bool {
        guard index >= 0, index + pattern.utf8.count <= bytes.count else { return false }
        return zip(bytes[index...], pattern.utf8).allSatisfy { lowercased($0) == lowercased($1) }
    }

    /// `byte` lowercased when it's an ASCII capital letter.
    private static func lowercased(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
    }

    /// `text` with numeric and common named HTML entities decoded.
    private static func decodingEntities(_ text: String) -> String {
        let named = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
                     "&ndash;": "–", "&mdash;": "—", "&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘",
                     "&rdquo;": "”", "&ldquo;": "“", "&copy;": "©"]
        let decoded = named.reduce(text) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
            .replacing(/&#(x?)([0-9a-fA-F]+);/) { match in
                let scalar = UInt32(match.output.2, radix: match.output.1.isEmpty ? 10 : 16).flatMap(Unicode.Scalar.init)
                return scalar.map { String(Character($0)) } ?? String(match.output.0)
            }
        return decoded.replacingOccurrences(of: "&amp;", with: "&")
    }
}

private extension String {
    /// The string with every run of whitespace turned into one space.
    var collapsingWhitespace: String {
        replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// The string with spaces collapsed, lines trimmed and at most one blank line in a row.
    var collapsingLines: String {
        replacing(/[ \t\u{a0}]+/, with: " ")
            .replacing(/[ ]*\n[ ]*/, with: "\n")
            .replacing(/\n{3,}/, with: "\n\n")
    }
}

/// Reads the front tab of the user's browser.
struct BrowserTabTool: Tool {
    /// A browser whose front tab AppleScript can read.
    private struct ScriptableBrowser {
        /// Its bundle identifier.
        let bundleIdentifier: String
        /// A script returning the front tab's title and URL on two lines.
        let script: String

        /// Safari, whose dictionary calls the front tab `front document`.
        static let safari = ScriptableBrowser(
            bundleIdentifier: "com.apple.Safari",
            script: "tell application \"Safari\" to tell front document to return (name as text) & linefeed & (URL as text)"
        )

        /// A Chromium-family browser called `appName`, whose dictionary has `active tab of front window`.
        static func chromium(_ bundleIdentifier: String, appName: String) -> ScriptableBrowser {
            ScriptableBrowser(
                bundleIdentifier: bundleIdentifier,
                script: "tell application \"\(appName)\" to tell active tab of front window to return (title as text) & linefeed & (URL as text)"
            )
        }
    }

    /// The browsers it knows how to read.
    private static let browsers: [ScriptableBrowser] = [
        .safari,
        .chromium("com.google.Chrome", appName: "Google Chrome"),
        .chromium("company.thebrowser.Browser", appName: "Arc"),
        .chromium("com.microsoft.edgemac", appName: "Microsoft Edge"),
        .chromium("com.brave.Browser", appName: "Brave Browser"),
        .chromium("org.chromium.Chromium", appName: "Chromium"),
    ]

    let name = "get_browser_tab"
    let description = """
        Gets the title and URL of the user's current browser tab. Call it when they say "this page" or "the site I'm \
        on"; then fetch_web_page to read it.
        """
    var parameters: JSONValue { Schema.object() }

    /// Its result carries the tab's title and address, which the page chose.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    func activity(for input: ToolInput) -> String {
        "Reading the browser tab"
    }

    func run(_ input: ToolInput) async throws -> String {
        let match = RunningApps.regular.lazy.compactMap { app in
            Self.browsers.first { $0.bundleIdentifier == app.bundleIdentifier }.map { (app.localizedName ?? "Browser", $0) }
        }.first
        guard let (appName, browser) = match else {
            throw ToolError("No supported browser is running (Safari, Chrome, Arc, Edge, Brave or Chromium).")
        }
        let output: String
        do {
            output = try await AppleScript.run(browser.script)
        } catch {
            throw ToolError("""
                Couldn't read \(appName)'s tab: \(error.localizedDescription) \
                If it has no window open, there's no tab to read. Otherwise the user can allow macobar to control \(appName) \
                in System Settings → Privacy & Security → Automation.
                """)
        }
        let lines = output.split(separator: "\n", maxSplits: 1).map(String.init)
        return "Browser: \(appName)\nTitle: \(lines.first ?? "")\nURL: \(lines.dropFirst().first ?? "")"
    }
}
