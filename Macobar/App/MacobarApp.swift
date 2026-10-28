import AppKit

/// Entry point: runs macobar as a background app whose only UI lives in the Dock.
@main
@MainActor
enum MacobarApp {
    /// Keeps the delegate alive for the app's lifetime, since NSApplication holds it weakly.
    private static let delegate = AppDelegate()

    /// Starts the AppKit run loop.
    static func main() {
        let application = NSApplication.shared
        application.delegate = delegate
        application.run()
    }
}

/// Bridges AppKit's launch and quit events to the app assembly.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Every module, built once at launch.
    private let assembly = AppAssembly()
    /// Turns `kill` and Ctrl-C into a normal quit.
    private let terminationSignals = TerminationSignals()

    /// Starts macobar once AppKit is ready.
    func applicationDidFinishLaunching(_ notification: Notification) {
        terminationSignals.quitOnSignal()
        Task { await assembly.start() }
    }

    /// Cleans up however macobar quits: the menu, closing setup, logout, or a signal.
    func applicationWillTerminate(_ notification: Notification) {
        assembly.stop()
    }
}
