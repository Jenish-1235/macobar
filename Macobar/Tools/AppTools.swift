import AppKit

/// Launches an app, or brings it to the front when it's already running.
struct OpenAppTool: Tool {
    /// Folders searched for installed apps, in order.
    private static let applicationFolders = [
        "/Applications",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    /// Name the model calls it by.
    let name = "open_app"
    /// When to call it and what it returns.
    let description = "Launches an app or brings it to the front."

    /// Takes the app's name or bundle ID.
    var parameters: JSONValue {
        Schema.object(["name": Schema.string("App name, e.g. \"Notes\", or bundle ID.")], required: ["name"])
    }

    /// Names the app being opened.
    func activity(for input: ToolInput) -> String {
        "Opening \(input.string("name") ?? "an app")"
    }

    /// Finds the app on disk and opens it.
    func run(_ input: ToolInput) async throws -> String {
        let name = try input.requiredString("name")
        guard let url = Self.applicationURL(named: name) else {
            throw ToolError("No app named \(name) is installed. Check the spelling or pass its bundle ID.")
        }
        let app = try await bringToFront(applicationAt: url)
        return "Opened \(app.localizedName ?? name)."
    }

    /// The installed app called `name` (case-insensitive, ".app" optional), or the app with that bundle ID.
    private static func applicationURL(named name: String) -> URL? {
        let wantedName = (name as NSString).deletingPathExtension.lowercased()
        for folder in applicationFolders {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            if let file = files.first(where: { $0.hasSuffix(".app") && ($0 as NSString).deletingPathExtension.lowercased() == wantedName }) {
                return URL(fileURLWithPath: folder).appendingPathComponent(file)
            }
        }
        guard name.contains("."), !name.contains(" ") else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: name)
    }
}

/// Switches to, hides, shows or quits a running app.
struct ControlAppTool: Tool {
    /// What can be done to a running app.
    private enum Action: String, CaseIterable {
        /// Bring it to the front.
        case activate
        /// Hide its windows.
        case hide
        /// Show its hidden windows.
        case unhide
        /// Ask it to quit.
        case quit
    }

    /// Name the model calls it by.
    let name = "control_app"
    /// When to call it and what it returns.
    let description = "Switches to, hides, unhides or quits a running app; use open_app if it isn't running."

    /// Takes the app's name and the action.
    var parameters: JSONValue {
        Schema.object([
            "name": Schema.string("Running app's name."),
            "action": Schema.oneOf(Action.allCases.map(\.rawValue), "What to do."),
        ], required: ["name", "action"])
    }

    /// Quitting may lose the user's work, so it asks first.
    func risk(for input: ToolInput) -> ToolRisk {
        Action(rawValue: input.string("action") ?? "") == .quit ? .confirmOnce : .none
    }

    /// Names the action and the app.
    func activity(for input: ToolInput) -> String {
        let appName = input.string("name") ?? "an app"
        switch Action(rawValue: input.string("action") ?? "") {
        case .activate: return "Switching to \(appName)"
        case .hide: return "Hiding \(appName)"
        case .unhide: return "Showing \(appName)"
        case .quit: return "Quitting \(appName)"
        case nil: return "Controlling \(appName)"
        }
    }

    /// Applies the action to the running app.
    func run(_ input: ToolInput) async throws -> String {
        let actionName = try input.requiredString("action")
        guard let action = Action(rawValue: actionName) else {
            throw ToolError("Unknown action \"\(actionName)\". Use one of: \(Action.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        let app = try RunningApps.find(input.requiredString("name"))
        let appName = app.localizedName ?? "The app"
        switch action {
        case .activate:
            guard let url = app.bundleURL else {
                guard app.activate() else { throw ToolError("\(appName) didn't come to the front.") }
                return "Switched to \(appName)."
            }
            _ = try await bringToFront(applicationAt: url)
            return "Switched to \(appName)."
        case .hide:
            guard !app.isHidden else { return "\(appName) is already hidden." }
            guard app.hide() else { throw ToolError("\(appName) refused to hide.") }
            return "Hid \(appName)."
        case .unhide:
            guard app.isHidden else { return "\(appName) isn't hidden." }
            guard app.unhide() else { throw ToolError("\(appName) refused to unhide.") }
            return "Showed \(appName)."
        case .quit:
            guard app.terminate() else { throw ToolError("\(appName) refused to quit.") }
            return "Asked \(appName) to quit; it may ask the user to save first."
        }
    }
}

/// Lists the apps the user has running.
struct ListAppsTool: Tool {
    /// Name the model calls it by.
    let name = "list_running_apps"
    /// When to call it and what it returns.
    let description = "Lists running apps, frontmost first, marking hidden ones. Use it to get an app's exact name."

    /// Takes no arguments.
    var parameters: JSONValue { Schema.object() }

    /// Describes the lookup.
    func activity(for input: ToolInput) -> String { "Listing running apps" }

    /// One line per running app.
    func run(_ input: ToolInput) async throws -> String {
        let lines = RunningApps.regular.map { app in
            let name = app.localizedName ?? app.bundleIdentifier ?? "Unknown app"
            let notes = [app.isActive ? "frontmost" : nil, app.isHidden ? "hidden" : nil].compactMap(\.self)
            return notes.isEmpty ? name : "\(name) (\(notes.joined(separator: ", ")))"
        }
        return lines.isEmpty ? "No apps are running." : lines.joined(separator: "\n")
    }
}

/// Launches or activates the app at `url` through Launch Services, which brings it forward even when macobar isn't active.
private func bringToFront(applicationAt url: URL) async throws -> NSRunningApplication {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    do {
        return try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    } catch {
        throw ToolError("Couldn't open \(url.deletingPathExtension().lastPathComponent): \(error.localizedDescription)")
    }
}
