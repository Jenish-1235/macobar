import AppKit
import ScreenCaptureKit

/// What look_at_screen captures.
enum LookTarget: String, CaseIterable, Sendable {
    /// The whole display the pointer is on.
    case screen
    /// The front app's front window.
    case frontWindow = "front_window"
}

/// A full-resolution screenshot and the part of the screen it shows.
struct CapturedScreen {
    /// The picture.
    let image: CGImage
    /// The area it shows, in screen points with a top-left origin on the main screen.
    let area: CGRect
    /// What it shows, e.g. "Safari's front window".
    let subject: String
}

/// Captures a display or window with ScreenCaptureKit, always leaving out macobar's own windows.
enum ScreenImageCapture {
    /// Captures `target`: the pointer's display, or `app`'s on-screen window at `windowFrame` (its first window if none matches).
    static func capture(_ target: LookTarget, app: NSRunningApplication?, windowFrame: CGRect?) async throws -> CapturedScreen {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw ToolError("""
                macobar needs Screen Recording access. Ask the user to allow macobar in System Settings → Privacy & \
                Security → Screen & System Audio Recording (choosing Quit & Reopen if asked), then try again.
                """)
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let (filter, area, subject) = switch target {
        case .screen: try displayFilter(in: content)
        case .frontWindow: try windowFilter(of: app, at: windowFrame, in: content)
        }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return CapturedScreen(image: image, area: area, subject: subject)
    }

    /// A filter for the display under the pointer with every macobar window left out, and that display's frame.
    private static func displayFilter(in content: SCShareableContent) throws -> (SCContentFilter, CGRect, String) {
        var pointerDisplayID = CGMainDisplayID()
        var displayCount: UInt32 = 0
        if let pointer = CGEvent(source: nil)?.location {
            CGGetDisplaysWithPoint(pointer, 1, &pointerDisplayID, &displayCount)
        }
        guard let display = content.displays.first(where: { $0.displayID == pointerDisplayID }) ?? content.displays.first else {
            throw ToolError("No display is available to capture.")
        }
        let macobar = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        return (SCContentFilter(display: display, excludingApplications: macobar, exceptingWindows: []), display.frame, "the screen")
    }

    /// A filter for `app`'s window at `frame` (else its first normal window), that window's frame, and what it shows.
    private static func windowFilter(of app: NSRunningApplication?, at frame: CGRect?, in content: SCShareableContent) throws -> (SCContentFilter, CGRect, String) {
        guard let app else {
            throw ToolError("No other app is in front. Ask the user to bring it forward, or use target screen.")
        }
        let name = app.localizedName ?? "The app"
        let windows = content.windows.filter { $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == 0 }
        guard let window = windows.first(where: { $0.frame == frame }) ?? windows.first else {
            throw ToolError("\(name) has no window on screen. Ask the user to show one, or use target screen.")
        }
        return (SCContentFilter(desktopIndependentWindow: window), window.frame, "\(name)'s front window")
    }
}
