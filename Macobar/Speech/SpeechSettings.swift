import Foundation

/// Whether Macie reads her replies aloud and in which voice, kept in preferences.
struct SpeechSettings: Sendable {
    /// Preferences key for the switch; replies stay silent until the user turns it on.
    private static let speaksRepliesKey = "speaksReplies"
    /// Preferences key holding the chosen voice's identifier.
    private static let voiceIdentifierKey = "speechVoiceIdentifier"

    /// Whether replies are read aloud.
    var speaksReplies: Bool {
        get { UserDefaults.standard.bool(forKey: Self.speaksRepliesKey) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: Self.speaksRepliesKey) }
    }

    /// The voice the user picked, as an `AVSpeechSynthesisVoice` identifier, or nil for the best installed one.
    var voiceIdentifier: String? {
        UserDefaults.standard.string(forKey: Self.voiceIdentifierKey)
    }
}
