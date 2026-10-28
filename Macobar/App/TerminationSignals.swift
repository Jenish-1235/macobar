import AppKit

/// Turns SIGTERM and SIGINT (`kill`, Ctrl-C) into a normal quit, so the Dock gap is still removed.
@MainActor
final class TerminationSignals {
    /// One source per signal, kept alive for the app's lifetime.
    private var sources: [any DispatchSourceSignal] = []

    /// Quits through AppKit when either signal arrives, instead of exiting on the spot.
    func quitOnSignal() {
        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
            source.resume()
            sources.append(source)
        }
    }
}
