import Vision

/// Finds lines of text in a screenshot with Vision OCR, for content Accessibility can't see.
enum RecognizedTextTargets {
    /// The text lines in `image`, which shows `area` of the screen, as targets in screen points.
    static func targets(in image: CGImage, showing area: CGRect) async throws -> [ScreenTarget] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        return try await request.perform(on: image)
            .filter { !$0.transcript.isEmpty }
            .map { observation in
                let frame = ScreenCoordinates.screenRect(forNormalized: observation.boundingBox.cgRect, in: area)
                return ScreenTarget(kind: .text, label: observation.transcript, frame: frame, source: .textRecognition)
            }
    }
}
