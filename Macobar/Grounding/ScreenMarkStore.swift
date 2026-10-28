import Synchronization

/// The marks from the latest look at the screen, so later calls can say "mark 12"; they expire after `lifetime` or at the next look.
final class ScreenMarkStore: Sendable {
    /// Marks and when they were taken.
    private struct Snapshot {
        /// The marks, numbered from 1.
        let marks: [ScreenMark]
        /// When the screen was looked at.
        let takenAt: ContinuousClock.Instant
    }

    /// How long marks stay valid; the screen has likely changed by then.
    static let lifetime = Duration.seconds(120)

    /// The latest marks, if any.
    private let latest = Mutex<Snapshot?>(nil)

    /// Replaces the marks with `marks`, taken at `now`.
    func replace(with marks: [ScreenMark], at now: ContinuousClock.Instant = .now) {
        latest.withLock { $0 = Snapshot(marks: marks, takenAt: now) }
    }

    /// Mark `number` from the latest look, or an error telling the model to look again.
    func mark(_ number: Int, at now: ContinuousClock.Instant = .now) throws -> ScreenMark {
        guard let snapshot = latest.withLock({ $0 }) else {
            throw ToolError("There are no marks yet. Call look_at_screen first, then use its mark numbers.")
        }
        guard now - snapshot.takenAt <= Self.lifetime else {
            throw ToolError("Marks expire 2 minutes after look_at_screen. Call look_at_screen again for fresh marks.")
        }
        guard let mark = snapshot.marks.first(where: { $0.number == number }) else {
            throw ToolError("There is no mark \(number); the last look had \(snapshot.marks.count) marks. Call look_at_screen again if the screen changed.")
        }
        return mark
    }
}
