import Foundation

/// Why the shortcut or listening couldn't start, with how to fix it.
enum VoiceError: LocalizedError {
    /// Another app holds Option-Space, or the system refused it; carries the Carbon status.
    case hotkeyUnavailable(OSStatus)
    /// The user turned microphone access off for macobar.
    case microphoneDenied
    /// No input device is connected or selected.
    case noMicrophone
    /// This Mac can't run on-device speech recognition.
    case speechUnavailable
    /// Neither the user's language nor US English is supported on this Mac.
    case languageUnsupported
    /// The microphone's audio can't be converted for the recognizer.
    case audioFormatUnsupported

    /// The message shown to the user.
    var errorDescription: String? {
        switch self {
        case .hotkeyUnavailable(let status):
            "Couldn't use Option-Space as a shortcut (error \(status)). Quit the app that uses it, then relaunch macobar."
        case .microphoneDenied:
            "macobar can't hear you. Allow it in System Settings → Privacy & Security → Microphone, then hold Option-Space again."
        case .noMicrophone:
            "No microphone found. Pick an input in System Settings → Sound → Input, then try again."
        case .speechUnavailable:
            "Speech recognition isn't available on this Mac. Tap Option-Space and type instead."
        case .languageUnsupported:
            "On-device speech recognition doesn't support your language or US English on this Mac. Tap Option-Space and type instead."
        case .audioFormatUnsupported:
            "Couldn't read audio from this microphone. Pick another input in System Settings → Sound → Input."
        }
    }
}
