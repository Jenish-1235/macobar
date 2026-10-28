import Synchronization

/// The tool calls made in one scenario, in order; shared by its fake tools.
final class CallLog: Sendable {
    /// Calls so far.
    private let recorded = Mutex<[RecordedCall]>([])

    /// Every call so far, oldest first.
    var calls: [RecordedCall] {
        recorded.withLock { $0 }
    }

    /// Adds `call` to the end.
    func record(_ call: RecordedCall) {
        recorded.withLock { $0.append(call) }
    }
}
