import AVFoundation

/// Reads a streamed reply aloud sentence by sentence, starting as soon as the first one is complete.
@MainActor
final class SpokenReply {
    /// How fast Macie talks: a little quicker than the system default.
    private static let rate = AVSpeechUtteranceDefaultSpeechRate * 1.1

    /// The on/off switch and chosen voice.
    private let settings = SpeechSettings()
    /// Speaks the queued sentences in order.
    private let synthesizer = AVSpeechSynthesizer()
    /// Collects fragments until a sentence is complete.
    private var splitter = SentenceSplitter()
    /// The voice for the current reply, chosen at its first sentence so newly installed voices are picked up.
    private var voice: AVSpeechSynthesisVoice?
    /// Whether the user cut the current reply off, so the rest of it stays silent.
    private var isInterrupted = false

    /// Whether replies are read aloud; saved, and turning it off goes quiet at once.
    var isOn: Bool {
        get { settings.speaksReplies }
        set {
            settings.speaksReplies = newValue
            if !newValue { stop() }
        }
    }

    /// Goes quiet and gets ready to read a new reply from its first sentence.
    func begin() {
        stop()
        isInterrupted = false
    }

    /// Adds streamed reply text and speaks every sentence it completes.
    func append(_ fragment: String) {
        splitter.append(fragment).forEach(speak)
    }

    /// Speaks what's left once the reply has ended.
    func finish() {
        if let rest = splitter.finish() { speak(rest) }
    }

    /// Goes quiet immediately and stays quiet for the rest of the reply, e.g. when the user types, talks or dismisses the card.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        splitter = SentenceSplitter()
        voice = nil
        isInterrupted = true
    }

    /// Queues `sentence` without code, links or Markdown, if speaking is on, the user hasn't cut in, and anything is left to say.
    private func speak(_ sentence: String) {
        let words = SpeakableText.from(sentence)
        guard isOn, !isInterrupted, !words.isEmpty else { return }
        voice = voice ?? ReplyVoice.best(preferredIdentifier: settings.voiceIdentifier)
        let utterance = AVSpeechUtterance(string: words)
        utterance.voice = voice
        utterance.rate = Self.rate
        synthesizer.speak(utterance)
    }
}
