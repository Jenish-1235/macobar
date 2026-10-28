import Testing

/// Verifies the Option-Space tap-versus-hold rule and how the transcript builds up.
struct VoiceTests {
    @Test("A quick tap focuses the field")
    func tapFocusesField() {
        var gesture = HotkeyGesture()
        #expect(gesture.press() == .waitForHold)
        #expect(gesture.release() == .focusField)
    }

    @Test("Holding past the threshold starts talking, and letting go finishes")
    func holdTalks() {
        var gesture = HotkeyGesture()
        #expect(gesture.press() == .waitForHold)
        #expect(gesture.holdThresholdPassed() == .startTalking)
        #expect(gesture.release() == .finishTalking)
    }

    @Test("A threshold that arrives after a tap does nothing")
    func lateThresholdIgnored() {
        var gesture = HotkeyGesture()
        _ = gesture.press()
        _ = gesture.release()
        #expect(gesture.holdThresholdPassed() == nil)
    }

    @Test("Key repeats while held are ignored")
    func repeatedPressIgnored() {
        var gesture = HotkeyGesture()
        _ = gesture.press()
        #expect(gesture.press() == nil)
        _ = gesture.holdThresholdPassed()
        #expect(gesture.press() == nil)
        #expect(gesture.release() == .finishTalking)
    }

    @Test("A release without a press does nothing, and the next press starts afresh")
    func strayReleaseIgnored() {
        var gesture = HotkeyGesture()
        #expect(gesture.release() == nil)
        _ = gesture.press()
        _ = gesture.holdThresholdPassed()
        _ = gesture.release()
        #expect(gesture.press() == .waitForHold)
        #expect(gesture.release() == .focusField)
    }

    @Test("The hold threshold is 0.35 seconds")
    func thresholdLength() {
        #expect(HotkeyGesture.holdThreshold == .milliseconds(350))
    }

    @Test("Volatile results replace each other; final ones are kept")
    func transcriptBuildsUp() {
        var transcript = Transcript()
        transcript.add("open", isFinal: false)
        transcript.add("open saf", isFinal: false)
        #expect(transcript.text == "open saf")
        transcript.add("Open Safari.", isFinal: true)
        transcript.add(" and", isFinal: false)
        #expect(transcript.text == "Open Safari. and")
        transcript.add(" And mail.", isFinal: true)
        #expect(transcript.text == "Open Safari. And mail.")
    }
}
