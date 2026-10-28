import Foundation

/// Reports the Mac's date, OS, battery, disk space and uptime.
struct SystemStatusTool: Tool {
    let name = "system_status"
    let description = """
        Gets the date, time and time zone, macOS version, battery, disk space and uptime. Call it whenever you need \
        today's date or the time.
        """
    var parameters: JSONValue { Schema.object() }

    func activity(for input: ToolInput) -> String {
        "Checking the Mac's status"
    }

    func run(_ input: ToolInput) async throws -> String {
        let now = Date.now
        let system = ProcessInfo.processInfo
        let uptime = DateComponentsFormatter()
        uptime.allowedUnits = [.day, .hour, .minute]
        uptime.unitsStyle = .abbreviated
        return [
            "Date: \(now.formatted(date: .complete, time: .shortened)) (\(TimeZone.current.identifier))",
            "macOS: \(system.operatingSystemVersionString)",
            "Battery: \(await batteryStatus())",
            "Startup disk: \(diskSpace())",
            "Uptime: \(uptime.string(from: system.systemUptime) ?? "unknown")",
        ].joined(separator: "\n")
    }

    /// Charge, state and time left from `pmset`, e.g. "85%; charging; 1:23 remaining (AC Power)".
    private func batteryStatus() async -> String {
        guard let report = try? await ProcessRunner.run("/usr/bin/pmset", ["-g", "batt"]) else { return "unknown" }
        let source = report.firstMatch(of: /'(.+?)'/).map { String($0.output.1) } ?? "unknown power source"
        guard let battery = report.firstMatch(of: /\t(\d+%;[^\n]*?)(?: present: \w+)?$/.anchorsMatchLineEndings()) else {
            return "none (\(source))"
        }
        return "\(battery.output.1) (\(source))"
    }

    /// Free and total space on the startup volume, e.g. "120 GB free of 494 GB".
    private func diskSpace() -> String {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else { return "unknown" }
        let freeText = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
        let totalText = ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
        return "\(freeText) free of \(totalText)"
    }
}

/// Changes volume and appearance, sleeps the display and locks the screen.
struct SystemControlTool: Tool {
    /// A system setting to change.
    private enum Action: String, CaseIterable {
        /// Set the output volume to `level`.
        case setVolume = "set_volume"
        /// Mute sound output.
        case mute
        /// Unmute sound output.
        case unmute
        /// Switch to Dark Mode.
        case darkMode = "dark_mode"
        /// Switch to Light Mode.
        case lightMode = "light_mode"
        /// Switch between Dark and Light Mode.
        case toggleDarkMode = "toggle_dark_mode"
        /// Turn the display off now.
        case sleepDisplay = "sleep_display"
        /// Lock the screen.
        case lockScreen = "lock_screen"
    }

    let name = "system_control"
    let description = """
        Sets volume, mute, Dark or Light Mode, sleeps the display or locks the screen. For other settings, open \
        their System Settings pane with open_url.
        """
    var parameters: JSONValue {
        Schema.object([
            "action": Schema.oneOf(Action.allCases.map(\.rawValue), "What to change."),
            "level": Schema.integer("0–100, for set_volume."),
        ], required: ["action"])
    }

    func risk(for input: ToolInput) -> ToolRisk {
        switch Action(rawValue: input.string("action") ?? "") {
        case .sleepDisplay, .lockScreen: .confirmOnce
        default: .none
        }
    }

    func activity(for input: ToolInput) -> String {
        switch Action(rawValue: input.string("action") ?? "") {
        case .setVolume: "Setting the volume to \(input.integer("level").map(String.init) ?? "?")%"
        case .mute: "Muting sound"
        case .unmute: "Unmuting sound"
        case .darkMode: "Switching to Dark Mode"
        case .lightMode: "Switching to Light Mode"
        case .toggleDarkMode: "Toggling Dark Mode"
        case .sleepDisplay: "Turning off the display"
        case .lockScreen: "Locking the screen"
        case nil: "Changing a system setting"
        }
    }

    func run(_ input: ToolInput) async throws -> String {
        guard let action = Action(rawValue: try input.requiredString("action")) else {
            throw ToolError("Unknown action. Use one of: \(Action.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        switch action {
        case .setVolume:
            guard let level = input.integer("level"), (0...100).contains(level) else {
                throw ToolError("set_volume needs a level from 0 to 100.")
            }
            _ = try await AppleScript.run("""
                on run argv
                    set volume output volume (item 1 of argv as integer)
                end run
                """, arguments: [String(level)])
            return "Volume set to \(level)%."
        case .mute:
            _ = try await AppleScript.run("set volume output muted true")
            return "Sound muted."
        case .unmute:
            _ = try await AppleScript.run("set volume output muted false")
            return "Sound unmuted."
        case .darkMode:
            try await setAppearance(to: "true")
            return "Dark Mode is on."
        case .lightMode:
            try await setAppearance(to: "false")
            return "Light Mode is on."
        case .toggleDarkMode:
            try await setAppearance(to: "not dark mode")
            return "Toggled Dark Mode."
        case .sleepDisplay:
            _ = try await ProcessRunner.run("/usr/bin/pmset", ["displaysleepnow"])
            return "Display turned off."
        case .lockScreen:
            _ = try await AppleScript.run(
                "tell application \"System Events\" to keystroke \"q\" using {control down, command down}")
            return "Screen locked."
        }
    }

    /// Sets System Events' dark mode to the AppleScript expression `value` (a fixed constant, never user text).
    private func setAppearance(to value: String) async throws {
        _ = try await AppleScript.run(
            "tell application \"System Events\" to tell appearance preferences to set dark mode to \(value)")
    }
}
