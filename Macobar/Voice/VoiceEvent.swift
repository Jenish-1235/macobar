/// What the voice shortcut reports to the chat bar.
enum VoiceEvent {
    /// Option-Space was tapped: bring the field forward and give it keyboard focus.
    case focusField
    /// Something to show before listening can start, e.g. download progress.
    case status(String)
    /// The microphone is on; Macie should look like she's listening.
    case listening
    /// Everything heard so far; replaces the previous transcript.
    case transcript(String)
    /// Listening ended; carries the prompt to send, or nil when nothing was heard.
    case finished(prompt: String?)
    /// The shortcut or listening failed; says how to fix it.
    case failed(String)
}
