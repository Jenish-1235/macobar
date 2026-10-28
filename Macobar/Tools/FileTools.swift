import AppKit
import PDFKit
import UniformTypeIdentifiers

/// The file URL for a model-given path, with a leading `~` expanded to the home folder.
private func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
}

/// Finds files with Spotlight.
struct SearchFilesTool: Tool {
    /// Most paths returned at once.
    private static let resultLimit = 30

    let name = "search_files"
    let description = """
        Finds files and folders with Spotlight, by name and contents. Call it when the user mentions a file without \
        its path, or to list a folder. Returns up to 30 paths only: call read_file on the best match to see what it says.
        """
    var parameters: JSONValue {
        Schema.object([
            "query": Schema.string("Words to find, e.g. \"invoice.pdf\"."),
            "name_only": Schema.boolean("Match names only. Default false."),
            "folder": Schema.string("Search only here, e.g. \"~/Documents\"."),
        ], required: ["query"])
    }

    /// Its result carries file names, which anyone who sent the user a file chose.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    func activity(for input: ToolInput) -> String {
        "Searching files for “\(input.string("query") ?? "")”"
    }

    func run(_ input: ToolInput) async throws -> String {
        let query = try input.requiredString("query")
        var arguments: [String] = []
        if let folder = input.string("folder") { arguments += ["-onlyin", fileURL(folder).path] }
        if input.bool("name_only") { arguments.append("-name") }
        arguments.append(query)
        let paths = try await ProcessRunner.run("/usr/bin/mdfind", arguments).split(separator: "\n")
        guard !paths.isEmpty else { return "No files found for “\(query)”." }
        let shown = paths.prefix(Self.resultLimit).joined(separator: "\n")
        return paths.count > Self.resultLimit ? "\(shown)\n…and \(paths.count - Self.resultLimit) more." : shown
    }
}

/// Opens a file in its default app or shows it in Finder.
struct OpenFileTool: Tool {
    /// Types whose default app runs them: apps, executables and scripts.
    private static let runnableTypes: [UTType] = [.executable, .script, .applicationBundle]
    /// Extensions that run code, install something or open a link or another file when opened.
    private static let runnableExtensions: Set = [
        "command", "tool", "terminal", "pkg", "mpkg", "mobileconfig", "jar", "shortcut", "workflow", "action",
        "prefpane", "saver", "osax", "scpt", "scptd", "applescript", "webloc", "inetloc", "fileloc", "url", "app",
        "afploc", "ftploc", "vncloc", "mailloc", "newsloc", "atloc",
    ]

    let name = "open_file"
    let description = """
        Opens a file or folder in its default app, or reveals it in Finder. Needs the path; use search_files first if \
        it isn't known.
        """
    var parameters: JSONValue {
        Schema.object([
            "path": Schema.string("Full path; ~ allowed."),
            "reveal": Schema.boolean("Select it in Finder instead. Default false."),
        ], required: ["path"])
    }

    /// Revealing and opening documents runs freely; opening anything that could run code asks every time.
    func risk(for input: ToolInput) -> ToolRisk {
        guard !input.bool("reveal") else { return .none }
        return Self.mayRunCode(fileURL(input.string("path") ?? "")) ? .confirmEveryTime : .none
    }

    func activity(for input: ToolInput) -> String {
        let fileName = fileURL(input.string("path") ?? "").lastPathComponent
        return input.bool("reveal") ? "Showing “\(fileName)” in Finder" : "Opening “\(fileName)”"
    }

    func run(_ input: ToolInput) async throws -> String {
        let url = fileURL(try input.requiredString("path"))
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError("Nothing exists at \(url.path). Use search_files to find it.")
        }
        if input.bool("reveal") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return "Showed \(url.path) in Finder."
        }
        guard NSWorkspace.shared.open(url) else { throw ToolError("No app could open \(url.path).") }
        return "Opened \(url.path)."
    }

    /// Whether opening `url` could run code, judged by what it opens: a symbolic link or Finder alias opens its target, so the target is checked too.
    private static func mayRunCode(_ url: URL) -> Bool {
        guard let isAlias = try? url.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile else { return true }
        guard isAlias else { return isRunnable(url) }
        guard let target = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]),
              (try? target.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == false else { return true }
        return isRunnable(url) || isRunnable(target)
    }

    /// Whether `url` itself is an app or other bundle, an executable, a script, an installer, or a file that opens a link.
    private static func isRunnable(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isExecutableKey, .contentTypeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return true }
        let isRunnableType = values.contentType.map { type in runnableTypes.contains { type.conforms(to: $0) } } ?? false
        if isRunnableType || runnableExtensions.contains(url.pathExtension.lowercased()) { return true }
        if values.isDirectory == true {
            // A plain folder opens in Finder; a bundle is safe only when it's a document, such as an .rtfd.
            return values.isPackage == true && values.contentType?.conforms(to: .content) != true
        }
        return values.isExecutable == true
    }
}

/// Reads the text of a document.
struct ReadFileTool: Tool {
    /// Most characters returned.
    private static let characterLimit = 30_000
    /// Largest file it will read, in bytes.
    private static let sizeLimit = 50_000_000
    /// Extensions read through `NSAttributedString`'s document import, with the importer each needs so a file can't pick another.
    private static let richTextTypes: [String: NSAttributedString.DocumentType] = [
        "rtf": .rtf, "rtfd": .rtfd, "doc": .docFormat, "docx": .officeOpenXML,
    ]
    /// Extensions read as HTML text without loading the page, so reading never fetches anything from the web.
    private static let htmlExtensions: Set = ["html", "htm"]

    let name = "read_file"
    let description = """
        Reads a file's text (plain text, code, PDF, RTF, Word, HTML, web archives), up to 30000 characters. Call it \
        to answer about, summarize or quote a file.
        """
    var parameters: JSONValue {
        Schema.object([
            "path": Schema.string("Full path; ~ allowed."),
        ], required: ["path"])
    }

    /// Reading private files (Library, hidden files such as keys and shell settings) asks every time; other files read freely.
    func risk(for input: ToolInput) -> ToolRisk {
        ProtectedLocations.isPrivate(fileURL(input.string("path") ?? "")) ? .confirmEveryTime : .none
    }

    /// Its result carries outside text the model will read, so later risky actions always ask.
    func readsOutsideContent(for input: ToolInput) -> Bool {
        true
    }

    func activity(for input: ToolInput) -> String {
        "Reading “\(fileURL(input.string("path") ?? "").lastPathComponent)”"
    }

    func run(_ input: ToolInput) async throws -> String {
        let url = fileURL(try input.requiredString("path"))
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]) else {
            throw ToolError("Nothing exists at \(url.path). Use search_files to find it.")
        }
        if values.isDirectory == true, url.pathExtension.lowercased() != "rtfd" {
            throw ToolError("\(url.path) is a folder. Use search_files with this folder to find files in it.")
        }
        // Devices and pipes (such as /dev/zero) never end, so reading one would hang or exhaust memory.
        if values.isDirectory != true, values.isRegularFile != true {
            throw ToolError("\(url.path) isn't a regular file, so it can't be read.")
        }
        if let size = values.fileSize, size > Self.sizeLimit {
            throw ToolError("\(url.path) is over 50 MB, too large to read.")
        }
        let text = try await extractText(from: url).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "\(url.lastPathComponent) has no readable text." }
        guard text.count > Self.characterLimit else { return text }
        return "\(text.prefix(Self.characterLimit))\n[Truncated: showing the first \(Self.characterLimit) of \(text.count) characters.]"
    }

    /// The text of the document at `url`, chosen by its extension.
    private func extractText(from url: URL) async throws -> String {
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "pdf" {
            guard let document = PDFDocument(url: url) else { throw ToolError("Couldn't open \(url.lastPathComponent) as a PDF.") }
            return document.string ?? ""
        }
        if Self.htmlExtensions.contains(fileExtension) {
            return ReadablePage(html: String(decoding: try Data(contentsOf: url), as: UTF8.self)).text
        }
        if fileExtension == "webarchive" {
            // The saved page's HTML is taken from the archive directly, since WebKit's import would fetch whatever it links to.
            let archive = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
            guard let page = archive?["WebMainResource"] as? [String: Any], let html = page["WebResourceData"] as? Data else {
                throw ToolError("\(url.lastPathComponent) isn't a web archive macobar can read.")
            }
            return ReadablePage(html: String(decoding: html, as: UTF8.self)).text
        }
        if let documentType = Self.richTextTypes[fileExtension] {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: documentType]
            return try NSAttributedString(url: url, options: options, documentAttributes: nil).string
        }
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        var encoding = String.Encoding.utf8
        guard let text = try? String(contentsOf: url, usedEncoding: &encoding) else {
            throw ToolError("\(url.lastPathComponent) isn't a text document macobar can read.")
        }
        return text
    }
}

/// Creates, moves, copies, trashes and writes files.
struct ManageFileTool: Tool {
    /// What to do to the file.
    private enum Action: String, CaseIterable {
        /// Make a new folder at `path`.
        case createFolder = "create_folder"
        /// Move or rename `path` to `destination`.
        case move
        /// Copy `path` to `destination`.
        case copy
        /// Move `path` to the Trash.
        case trash
        /// Save `text` as a file at `path`.
        case writeText = "write_text"
    }

    let name = "manage_file"
    let description = """
        Creates folders, moves (also renames), copies, trashes, or saves text as a file. Call it to organize, rename, \
        copy, delete or save files. write_text won't replace an existing file unless overwrite is true.
        """
    var parameters: JSONValue {
        Schema.object([
            "action": Schema.oneOf(Action.allCases.map(\.rawValue), "What to do."),
            "path": Schema.string("Full path to act on or create; ~ allowed."),
            "destination": Schema.string("For move/copy: new full path, or a folder to put it in."),
            "text": Schema.string("For write_text."),
            "overwrite": Schema.boolean("For write_text: replace an existing file. Default false."),
        ], required: ["action", "path"])
    }

    /// Trashing, overwriting and anything touching private files ask every time; other changes ask once.
    func risk(for input: ToolInput) -> ToolRisk {
        if affectedURLs(input).contains(where: ProtectedLocations.isPrivate) { return .confirmEveryTime }
        switch Action(rawValue: input.string("action") ?? "") {
        case .trash: return .confirmEveryTime
        case .writeText where input.bool("overwrite"): return .confirmEveryTime
        default: return .confirmOnce
        }
    }

    func activity(for input: ToolInput) -> String {
        let fileName = "“\(fileURL(input.string("path") ?? "").lastPathComponent)”"
        let destination = "“\(input.string("destination") ?? "")”"
        switch Action(rawValue: input.string("action") ?? "") {
        case .createFolder: return "Creating folder \(fileName)"
        case .move: return "Moving \(fileName) to \(destination)"
        case .copy: return "Copying \(fileName) to \(destination)"
        case .trash: return "Moving \(fileName) to the Trash"
        case .writeText: return "Writing \(fileName)"
        case nil: return "Changing \(fileName)"
        }
    }

    func run(_ input: ToolInput) async throws -> String {
        guard let action = Action(rawValue: try input.requiredString("action")) else {
            throw ToolError("Unknown action. Use one of: \(Action.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        let url = fileURL(try input.requiredString("path"))
        for affected in affectedURLs(input) {
            if let refusal = ProtectedLocations.refusal(forChanging: affected) { throw ToolError(refusal + " Tell the user.") }
        }
        let files = FileManager.default
        do {
            switch action {
            case .createFolder:
                try files.createDirectory(at: url, withIntermediateDirectories: true)
                return "Created folder \(url.path)."
            case .move:
                let destination = try destinationURL(for: url, input)
                try files.moveItem(at: url, to: destination)
                return "Moved to \(destination.path)."
            case .copy:
                let destination = try destinationURL(for: url, input)
                try files.copyItem(at: url, to: destination)
                return "Copied to \(destination.path)."
            case .trash:
                var trashedURL: NSURL?
                try files.trashItem(at: url, resultingItemURL: &trashedURL)
                guard let trashedPath = trashedURL?.path else { return "Moved \(url.path) to the Trash." }
                return "Moved \(url.path) to the Trash.\n\(UndoStep.trashLocationPrefix)\(trashedPath)."
            case .writeText:
                guard let text = input.rawString("text") else { throw ToolError("Missing required argument \"text\".") }
                if files.fileExists(atPath: url.path), !input.bool("overwrite") {
                    throw ToolError("\(url.path) already exists. Ask the user before replacing it, then set overwrite to true.")
                }
                try text.write(to: url, atomically: true, encoding: .utf8)
                return "Saved \(url.path)."
            }
        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError(error.localizedDescription)
        }
    }

    /// Every item the call changes: `path`, and for move and copy where it ends up.
    private func affectedURLs(_ input: ToolInput) -> [URL] {
        guard let path = input.string("path") else { return [] }
        let source = fileURL(path)
        guard input.string("destination") != nil, let destination = try? destinationURL(for: source, input) else { return [source] }
        return [source, destination]
    }

    /// Where `source` goes: `destination` itself, or inside it when it's an existing folder.
    private func destinationURL(for source: URL, _ input: ToolInput) throws -> URL {
        let destination = fileURL(try input.requiredString("destination"))
        let isFolder = (try? destination.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        return isFolder ? destination.appendingPathComponent(source.lastPathComponent) : destination
    }
}
