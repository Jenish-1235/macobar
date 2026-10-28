import AppKit

/// The system Dock process.
enum DockProcess {
    /// Bundle identifier of the Dock.
    static let bundleIdentifier = "com.apple.dock"

    /// The running Dock, or nil while it restarts.
    static var running: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    }

    /// How long a freshly started Dock is left alone: about 5 seconds in it saves the layout it loaded, over any change made before that.
    private static let settleTime: TimeInterval = 7
    /// macobar's own preference holding when it last restarted the Dock, so a quick relaunch sees a restart its last run asked for.
    private static let lastRestartKey = "lastDockRestart"

    /// Waits until a Dock started after macobar's last restart has been running for `settleTime`, giving up after 15 seconds; the Dock being restarted still looks settled until it exits.
    static func waitUntilSettled() async {
        let lastRestart = UserDefaults.standard.object(forKey: lastRestartKey) as? Date ?? .distantPast
        for _ in 0..<60 {
            if let dock = running, let started = startDate(of: dock.processIdentifier),
               started > lastRestart, Date.now.timeIntervalSince(started) >= settleTime { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// When the process `pid` started, from the kernel; the Dock has no `launchDate`, since launchd starts it.
    private static func startDate(of pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var request: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&request, u_int(request.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    /// Restarts the Dock so it reloads its preferences; macOS relaunches it automatically.
    static func restart() {
        guard let dock = running else { return }
        UserDefaults.standard.set(Date.now, forKey: lastRestartKey)
        kill(dock.processIdentifier, SIGTERM)
    }
}
