import AVFoundation

/// Chooses the voice Macie speaks in: the user's pick, else the best installed voice for their language.
enum ReplyVoice {
    /// The voice with `preferredIdentifier` if installed; otherwise Personal Voice (if already allowed), then premium, enhanced, default.
    static func best(preferredIdentifier: String?) -> AVSpeechSynthesisVoice? {
        if let preferredIdentifier, let voice = AVSpeechSynthesisVoice(identifier: preferredIdentifier) { return voice }
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let languageCode = Locale(identifier: language).language.languageCode
        let allowsPersonalVoice = AVSpeechSynthesizer.personalVoiceAuthorizationStatus == .authorized
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            Locale(identifier: voice.language).language.languageCode == languageCode
                && !voice.voiceTraits.contains(.isNoveltyVoice)
                && (allowsPersonalVoice || !voice.voiceTraits.contains(.isPersonalVoice))
        }
        return candidates.max { rank($0, for: language) < rank($1, for: language) } ?? AVSpeechSynthesisVoice(language: language)
    }

    /// Orders voices: Personal Voice above premium, enhanced and default quality, then the user's own region first.
    private static func rank(_ voice: AVSpeechSynthesisVoice, for language: String) -> (Int, Int) {
        let quality = voice.voiceTraits.contains(.isPersonalVoice) ? AVSpeechSynthesisVoiceQuality.premium.rawValue + 1 : voice.quality.rawValue
        return (quality, voice.language == language ? 1 : 0)
    }
}
