/// Streams Dock geometry changes, checking quickly while the Dock moves and slowly at rest.
@MainActor
final class DockObserver {
    /// Check interval while nothing is changing.
    private static let restingInterval: Duration = .milliseconds(100)
    /// Check interval while the Dock is animating, so the chat bar keeps up frame by frame.
    private static let movingInterval: Duration = .milliseconds(16)
    /// How long after the last change the Dock still counts as moving.
    private static let settleDuration: Duration = .seconds(1)
    /// Source of geometry snapshots.
    private let reader: DockReader

    /// Creates an observer that reads the Dock through `reader`.
    init(reader: DockReader) {
        self.reader = reader
    }

    /// Emits geometry whenever it changes; nil means the Dock or gap isn't currently visible.
    func geometryUpdates() -> AsyncStream<DockGeometry?> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                var lastGeometry = reader.readGeometry()
                var lastChange = ContinuousClock.now
                continuation.yield(lastGeometry)
                while !Task.isCancelled {
                    let isMoving = ContinuousClock.now - lastChange < Self.settleDuration
                    try? await Task.sleep(for: isMoving ? Self.movingInterval : Self.restingInterval) // Throws only on cancellation.
                    let geometry = reader.readGeometry()
                    guard geometry != lastGeometry else { continue }
                    lastGeometry = geometry
                    lastChange = .now
                    continuation.yield(geometry)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
