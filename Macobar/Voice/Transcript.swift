/// What has been heard so far: settled text plus the latest guess at the words still being spoken.
struct Transcript {
    /// Text the recognizer won't change any more.
    private(set) var finalized = ""
    /// The recognizer's current guess for the words after `finalized`.
    private(set) var volatile = ""

    /// Everything heard so far, as it should appear in the field.
    var text: String { finalized + volatile }

    /// Adds a result: a final one settles its text, a volatile one replaces the previous guess.
    mutating func add(_ text: String, isFinal: Bool) {
        if isFinal {
            finalized += text
            volatile = ""
        } else {
            volatile = text
        }
    }
}
