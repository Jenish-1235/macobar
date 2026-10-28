import Foundation

/// The Option-Space shortcut: tap to focus the field, hold to talk and send what was heard on release.
@MainActor
final class VoiceController {
    /// Longest the microphone stays on for one hold; a release macOS never delivers (Secure Keyboard Entry swallows it) can't leave it listening.
    private static let longestListening = Duration.seconds(120)

    /// Where every event goes.
    private let onEvent: (VoiceEvent) -> Void
    /// Turns speech into text while the key is held.
    private let speech = SpeechInput()
    /// The registered shortcut, while started.
    private var hotkey: GlobalHotkey?
    /// Tells taps from holds.
    private var gesture = HotkeyGesture()
    /// Waits out the hold threshold after a press.
    private var holdTimer: Task<Void, Never>?
    /// Getting ready to listen, from the threshold until the microphone is on.
    private var startup: Task<Void, Never>?
    /// Stopping and collecting the transcript after release.
    private var finishing: Task<Void, Never>?
    /// Turns the microphone off when a hold runs past `longestListening`.
    private var listeningLimit: Task<Void, Never>?

    /// Creates a stopped controller that reports to `onEvent`.
    init(onEvent: @escaping (VoiceEvent) -> Void) {
        self.onEvent = onEvent
    }

    /// Registers Option-Space, reporting `.failed` if the system refuses it.
    func start() {
        guard hotkey == nil else { return }
        do {
            hotkey = try GlobalHotkey(
                onPress: { [weak self] in self?.handle(self?.gesture.press()) },
                onRelease: { [weak self] in self?.handle(self?.gesture.release()) }
            )
        } catch {
            onEvent(.failed(error.localizedDescription))
        }
    }

    /// Unregisters the shortcut; a hold in progress ends as if the key came up.
    func stop() {
        hotkey?.stop()
        hotkey = nil
        holdTimer?.cancel()
        if gesture.release() == .finishTalking { finishTalking() }
    }

    /// Carries out what the gesture decided.
    private func handle(_ action: HotkeyGesture.Action?) {
        switch action {
        case .waitForHold: waitForHold()
        case .focusField:
            holdTimer?.cancel()
            onEvent(.focusField)
        case .startTalking:
            startTalking()
            limitListening()
        case .finishTalking: finishTalking()
        case nil: break
        }
    }

    /// Reports the hold threshold unless the key came up first.
    private func waitForHold() {
        holdTimer = Task { [weak self] in
            try? await Task.sleep(for: HotkeyGesture.holdThreshold)
            guard !Task.isCancelled, let self else { return }
            handle(gesture.holdThresholdPassed())
        }
    }

    /// Turns the microphone on once the last session has finished.
    private func startTalking() {
        let previous = finishing
        startup = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                try await speech.start(
                    onStatus: { [weak self] in self?.onEvent(.status($0)) },
                    onText: { [weak self] in self?.onEvent(.transcript($0)) }
                )
                onEvent(.listening)
            } catch is CancellationError {
                onEvent(.finished(prompt: nil))
            } catch {
                onEvent(.failed(error.localizedDescription))
            }
        }
    }

    /// Ends the hold without sending once it has lasted `longestListening`, since the key's release was likely lost.
    private func limitListening() {
        listeningLimit = Task { [weak self] in
            try? await Task.sleep(for: Self.longestListening)
            guard !Task.isCancelled, let self, gesture.release() == .finishTalking else { return }
            finishTalking(sendsPrompt: false)
        }
    }

    /// Stops listening and sends what was heard unless `sendsPrompt` is false; a key released before the microphone came on just ends it.
    private func finishTalking(sendsPrompt: Bool = true) {
        listeningLimit?.cancel()
        listeningLimit = nil
        let startup = startup
        startup?.cancel()
        self.startup = nil
        finishing = Task { [weak self] in
            await startup?.value
            guard let self, let transcript = await speech.stop() else { return }
            onEvent(.transcript(transcript))
            onEvent(.finished(prompt: transcript.isEmpty || !sendsPrompt ? nil : transcript))
        }
    }
}
