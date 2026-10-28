import AppKit

/// Looks at the screen and finds the numbered targets the model can point at, click, scroll or drag.
enum ScreenMarks {
    /// Captures `target`, marks the front window's Accessibility elements and the recognized text not already covered,
    /// keeps the marks in `store`, and returns them with the annotated image, what it shows, and its area in screen points.
    static func look(at target: LookTarget, storingIn store: ScreenMarkStore) async throws -> (marks: [ScreenMark], image: ToolImage, subject: String, area: CGRect) {
        let frontApp = RunningApps.frontmost.flatMap { $0.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : $0 }
        let window = switch target {
        case .screen: frontApp.flatMap { try? AccessibilityElement.focusedWindow(of: $0) }
        case .frontWindow: try frontApp.map(AccessibilityElement.focusedWindow(of:))
        }
        let windowFrame = window.flatMap(AccessibilityTargets.frame(of:))
        let capture = try await ScreenImageCapture.capture(target, app: frontApp, windowFrame: windowFrame)
        let accessibility = window.map { AccessibilityTargets.targets(in: $0, within: capture.area.intersection(windowFrame ?? capture.area)) } ?? []
        let recognizedText = try await RecognizedTextTargets.targets(in: capture.image, showing: capture.area)
        let marks = MarkSelection.marks(accessibility: accessibility, recognizedText: recognizedText, visibleArea: capture.area)
        let image = try MarkAnnotator.annotatedJPEG(of: capture.image, showing: capture.area, marks: marks)
        store.replace(with: marks)
        return (marks, image, capture.subject, capture.area)
    }
}
