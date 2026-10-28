/// Tells a tap of the hotkey from a hold: a quick tap focuses the field, holding it talks.
struct HotkeyGesture {
    /// What the controller should do after a key event.
    enum Action: Equatable {
        /// Wait `holdThreshold`, then report it with `holdThresholdPassed()`.
        case waitForHold
        /// The key was tapped: bring the field forward for typing.
        case focusField
        /// The key is still down at the threshold: start listening.
        case startTalking
        /// The held key came up: stop listening and send what was heard.
        case finishTalking
    }

    /// Where the key is in a press.
    private enum Phase {
        /// The key is up.
        case idle
        /// The key is down, not yet long enough to count as a hold.
        case pressed
        /// The key has been held past the threshold.
        case holding
    }

    /// How long the key must stay down to count as a hold.
    static let holdThreshold = Duration.milliseconds(350)

    /// Where the key is now.
    private var phase = Phase.idle

    /// The key went down; repeats while it's already down are ignored.
    mutating func press() -> Action? {
        guard phase == .idle else { return nil }
        phase = .pressed
        return .waitForHold
    }

    /// The hold threshold passed; starts talking only if the same press is still down.
    mutating func holdThresholdPassed() -> Action? {
        guard phase == .pressed else { return nil }
        phase = .holding
        return .startTalking
    }

    /// The key came up: a tap if it was quick, the end of talking if it was held.
    mutating func release() -> Action? {
        defer { phase = .idle }
        switch phase {
        case .idle: return nil
        case .pressed: return .focusField
        case .holding: return .finishTalking
        }
    }
}
