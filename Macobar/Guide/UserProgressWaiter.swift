import AppKit

/// Waits until the user does what a guided step asks, giving up at a timeout and stopping when cancelled.
enum UserProgressWaiter {
    /// Seconds to wait when no timeout is given.
    private static let defaultTimeoutSeconds = 60.0
    /// Longest wait allowed in seconds, so a forgotten walkthrough stops watching the user.
    private static let longestTimeoutSeconds = 300.0
    /// Shortest wait allowed in seconds.
    private static let shortestTimeoutSeconds = 1.0
    /// How often the front app, window and menus are checked (4 Hz).
    private static let quickPollInterval = Duration.milliseconds(250)
    /// How often the front window's text is searched, which costs more (2 Hz).
    private static let textPollInterval = Duration.milliseconds(500)

    /// The timeout for `seconds`, or 60 seconds when nil, kept between 1 and 300 seconds.
    static func timeout(seconds: Double?) -> Duration {
        .seconds(min(max(seconds ?? defaultTimeoutSeconds, shortestTimeoutSeconds), longestTimeoutSeconds))
    }

    /// Whether a click at `location` (AppKit global points, bottom-left origin) lands in `area` (global points, top-left origin).
    static func isClick(at location: CGPoint, inside area: CGRect, primaryScreenHeight: CGFloat) -> Bool {
        area.contains(CGPoint(x: location.x, y: primaryScreenHeight - location.y))
    }

    /// Watches for `expectation` until it happens, `timeout` passes, or the task is cancelled; throws when watching can't start.
    static func wait(for expectation: UserExpectation, timeout: Duration) async throws -> WaitOutcome {
        try AccessibilityElement.requirePermission()
        return try await withThrowingTaskGroup(of: WaitOutcome.self) { group in
            group.addTask { .matched(try await detect(expectation)) }
            group.addTask {
                try await Task.sleep(for: timeout)
                return .timedOut
            }
            defer { group.cancelAll() }
            do {
                return try await group.next() ?? .cancelled
            } catch is CancellationError {
                return .cancelled
            }
        }
    }

    /// Waits for `expectation` and returns what the user did; throws `CancellationError` when cancelled first.
    private static func detect(_ expectation: UserExpectation) async throws -> String {
        switch expectation {
        case .clickIn(let area): try await click(inside: area)
        case .appChange: try await appChange()
        case .windowChange: try await windowChange()
        case .menuOpen: try await poll(every: quickPollInterval) { FrontAppProbe.openMenu().map { "Opened \($0)" } }
        case .textAppears(let text): try await appearance(of: text)
        case .anyKey: try await firstGlobalEvent(.keyDown) { _ in "Pressed a key" }
        }
    }

    /// Waits for a left click inside `area`, ignoring clicks elsewhere.
    @MainActor
    private static func click(inside area: CGRect) async throws -> String {
        try await firstGlobalEvent(.leftMouseDown) { event in
            guard let primaryScreenHeight = NSScreen.screens.first?.frame.height,
                  isClick(at: event.locationInWindow, inside: area, primaryScreenHeight: primaryScreenHeight)
            else { return nil }
            return "Clicked in the marked area"
        }
    }

    /// Waits for an app other than the current frontmost one to come to the front.
    private static func appChange() async throws -> String {
        let startingApp = RunningApps.frontmost?.processIdentifier
        return try await poll(every: quickPollInterval) {
            guard let app = RunningApps.frontmost, app.processIdentifier != startingApp else { return nil }
            return "Switched to \(app.localizedName ?? "another app")"
        }
    }

    /// Waits for the front window to become another window, change its title, or close.
    private static func windowChange() async throws -> String {
        let startingWindow = FrontAppProbe.frontWindow()
        let startingTitle = startingWindow?.title
        return try await poll(every: quickPollInterval) {
            let window = FrontAppProbe.frontWindow()
            let isUnchanged = switch (startingWindow, window) {
            case (nil, nil): true
            case let (before?, after?): CFEqual(before.element, after.element) && after.title == startingTitle
            default: false
            }
            guard !isUnchanged else { return nil }
            return window.map { "The front window is now “\($0.title ?? "Untitled")”" } ?? "Closed the window"
        }
    }

    /// Waits for `text` to show in the front window, saying so when it was there from the start.
    private static func appearance(of text: String) async throws -> String {
        guard !FrontAppProbe.frontWindowContains(text) else { return "“\(text)” was already showing before the wait began" }
        return try await poll(every: textPollInterval) { FrontAppProbe.frontWindowContains(text) ? "“\(text)” appeared" : nil }
    }

    /// Runs `check` every `interval` until it describes a match; throws `CancellationError` when cancelled.
    private static func poll(every interval: Duration, _ check: () -> String?) async throws -> String {
        while true {
            if let match = check() { return match }
            try await Task.sleep(for: interval)
        }
    }

    /// The first global event of `mask` that `describe` turns into a match; the monitor is removed however the wait ends.
    @MainActor
    private static func firstGlobalEvent(_ mask: NSEvent.EventTypeMask, describedBy describe: @escaping @MainActor (NSEvent) -> String?) async throws -> String {
        let (matches, continuation) = AsyncStream.makeStream(of: String.self)
        let handler: (NSEvent) -> Void = { event in
            MainActor.assumeIsolated {
                if let match = describe(event) { continuation.yield(match) }
            }
        }
        guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) else {
            throw ToolError("macOS didn't let macobar watch for clicks and key presses. Check that macobar is allowed in System Settings › Privacy & Security › Accessibility.")
        }
        defer { NSEvent.removeMonitor(monitor) }
        for await match in matches { return match }
        throw CancellationError()
    }
}
