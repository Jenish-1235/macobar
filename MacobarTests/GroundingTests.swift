import ApplicationServices
import Foundation
import Testing

/// Verifies how screen targets become numbered marks, how mouse tools read places, and the coordinate conversions.
struct GroundingTests {
    /// The part of the screen every selection test looks at.
    private let visibleArea = CGRect(x: 0, y: 0, width: 1000, height: 800)

    /// A target found through Accessibility.
    private func control(_ kind: MarkKind, _ label: String, _ frame: CGRect) -> ScreenTarget {
        ScreenTarget(kind: kind, label: label, frame: frame, source: .accessibility)
    }

    /// A line of text found by OCR.
    private func recognized(_ label: String, _ frame: CGRect) -> ScreenTarget {
        ScreenTarget(kind: .text, label: label, frame: frame, source: .textRecognition)
    }

    @Test("Intersection over union is 1 for the same rectangle, 0 for apart ones, and a third for a half overlap")
    func intersectionOverUnion() {
        let square = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(MarkSelection.intersectionOverUnion(square, square) == 1)
        #expect(MarkSelection.intersectionOverUnion(square, CGRect(x: 20, y: 20, width: 10, height: 10)) == 0)
        #expect(abs(MarkSelection.intersectionOverUnion(square, CGRect(x: 5, y: 0, width: 10, height: 10)) - 1.0 / 3) < 1e-9)
    }

    @Test("Recognized text mostly overlapping an Accessibility target is dropped; text elsewhere is kept")
    func overlappingTextIsDropped() {
        let marks = MarkSelection.marks(
            accessibility: [control(.button, "", CGRect(x: 100, y: 100, width: 80, height: 24))],
            recognizedText: [recognized("Export", CGRect(x: 100, y: 102, width: 80, height: 20)),
                             recognized("Elsewhere", CGRect(x: 400, y: 400, width: 90, height: 20))],
            visibleArea: visibleArea)
        #expect(marks.map(\.target.label) == ["", "Elsewhere"])
    }

    @Test("A control's own title inside it is dropped, but other text inside controls is kept")
    func textInsideControls() {
        let marks = MarkSelection.marks(
            accessibility: [control(.button, "Export", CGRect(x: 100, y: 100, width: 80, height: 24)),
                            control(.text, "Export", CGRect(x: 110, y: 104, width: 60, height: 16)),
                            control(.row, "", CGRect(x: 0, y: 200, width: 400, height: 30)),
                            control(.textField, "Message", CGRect(x: 0, y: 300, width: 500, height: 40))],
            recognizedText: [recognized("Quarterly report", CGRect(x: 10, y: 205, width: 100, height: 20)),
                             recognized("Lunch at noon?", CGRect(x: 10, y: 310, width: 120, height: 20))],
            visibleArea: visibleArea)
        #expect(marks.map(\.target.label) == ["Export", "", "Quarterly report", "Message", "Lunch at noon?"])
    }

    @Test("Targets are cut to the visible area, and ones too small or outside it are dropped")
    func clipping() {
        let marks = MarkSelection.marks(
            accessibility: [control(.button, "Edge", CGRect(x: 990, y: 10, width: 40, height: 20)),
                            control(.button, "Away", CGRect(x: 2000, y: 2000, width: 40, height: 20)),
                            control(.button, "Tiny", CGRect(x: 50, y: 50, width: 3, height: 3))],
            recognizedText: [],
            visibleArea: visibleArea)
        #expect(marks.map(\.target.label) == ["Edge"])
        #expect(marks.first?.target.frame == CGRect(x: 990, y: 10, width: 10, height: 20))
    }

    @Test("Over the limit, controls beat text and labelled beat unlabelled, then numbers follow reading order")
    func rankingAndCapping() {
        let marks = MarkSelection.marks(
            accessibility: [control(.button, "OK", CGRect(x: 10, y: 50, width: 20, height: 20)),
                            control(.button, "", CGRect(x: 300, y: 10, width: 20, height: 20)),
                            control(.text, "Caption", CGRect(x: 10, y: 600, width: 300, height: 40))],
            recognizedText: [recognized("Big heading", CGRect(x: 10, y: 300, width: 600, height: 60))],
            visibleArea: visibleArea, limit: 2)
        #expect(marks.map(\.number) == [1, 2])
        #expect(marks.map(\.target.label) == ["", "OK"])
    }

    @Test("Among equally preferred targets, larger ones are kept")
    func largerFirst() {
        let marks = MarkSelection.marks(
            accessibility: [control(.button, "Small", CGRect(x: 10, y: 10, width: 20, height: 20)),
                            control(.button, "Large", CGRect(x: 100, y: 100, width: 120, height: 40))],
            recognizedText: [],
            visibleArea: visibleArea, limit: 1)
        #expect(marks.map(\.target.label) == ["Large"])
    }

    @Test("Marks on the same line are numbered left to right")
    func readingOrder() {
        let marks = MarkSelection.marks(
            accessibility: [control(.button, "Right", CGRect(x: 500, y: 10, width: 40, height: 20)),
                            control(.button, "Left", CGRect(x: 10, y: 10, width: 40, height: 20))],
            recognizedText: [],
            visibleArea: visibleArea)
        #expect(marks.map(\.target.label) == ["Left", "Right"])
    }

    @Test("Labels are flattened to one line and cut to 60 characters with an ellipsis")
    func labels() {
        #expect(control(.button, "  Save\nAs  ", .zero).label == "Save As")
        let long = control(.text, String(repeating: "a", count: 80), .zero).label
        #expect(long.count == 60)
        #expect(long.hasSuffix("…"))
    }

    @Test("A mark's summary and name show its kind, label and whole-point frame")
    func summary() {
        let labelled = ScreenMark(number: 12, target: control(.button, "Export", CGRect(x: 840, y: 112, width: 64, height: 22)))
        let unlabelled = ScreenMark(number: 3, target: control(.row, "", CGRect(x: 0.4, y: 0, width: 10, height: 10)))
        #expect(labelled.summary == "12 button 'Export' at (840,112,64,22)")
        #expect(labelled.name == "'Export'")
        #expect(unlabelled.summary == "3 row at (0,0,11,10)")
        #expect(unlabelled.name == "mark 3")
    }

    @Test("Accessibility roles map to mark kinds, with tab buttons as tabs and containers left out")
    func kinds() {
        #expect(MarkKind(role: kAXRadioButtonRole, subrole: "AXTabButton") == .tab)
        #expect(MarkKind(role: kAXRadioButtonRole, subrole: nil) == .radio)
        #expect(MarkKind(role: "AXLink", subrole: nil) == .link)
        #expect(MarkKind(role: kAXGroupRole, subrole: nil) == nil)
        #expect(MarkKind.text.isActionable == false)
    }

    @Test("A place is a mark, or x and y, under an optional prefix")
    func placeParsing() throws {
        #expect(try PointReference.optional(in: ToolInput(["mark": 12])) == .mark(12))
        #expect(try PointReference.optional(in: ToolInput(["x": 10, "y": .number(20.5)])) == .point(CGPoint(x: 10, y: 20.5)))
        let drag = ToolInput(["from_mark": 3, "to_x": 1, "to_y": 2])
        #expect(try PointReference.required(in: drag, prefix: "from_") == .mark(3))
        #expect(try PointReference.required(in: drag, prefix: "to_") == .point(CGPoint(x: 1, y: 2)))
        #expect(try PointReference.optional(in: ToolInput()) == nil)
    }

    @Test("A missing, half, doubled or zero place is an error")
    func badPlaces() {
        #expect(throws: ToolError.self) { try PointReference.required(in: ToolInput()) }
        #expect(throws: ToolError.self) { try PointReference.optional(in: ToolInput(["x": 10])) }
        #expect(throws: ToolError.self) { try PointReference.optional(in: ToolInput(["mark": 1, "x": 1, "y": 2])) }
        #expect(throws: ToolError.self) { try PointReference.optional(in: ToolInput(["mark": 0])) }
    }

    @Test("A mark resolves to its centre and a point to itself")
    func resolving() throws {
        let store = ScreenMarkStore()
        store.replace(with: [ScreenMark(number: 1, target: control(.button, "OK", CGRect(x: 100, y: 200, width: 40, height: 20)))])
        let fromMark = try PointReference.mark(1).resolve(in: store)
        #expect(fromMark.point == CGPoint(x: 120, y: 210))
        #expect(fromMark.mark?.target.label == "OK")
        let fromPoint = try PointReference.point(CGPoint(x: 5, y: 6)).resolve(in: store)
        #expect(fromPoint.point == CGPoint(x: 5, y: 6))
        #expect(fromPoint.mark == nil)
        #expect(PointReference.mark(1).name(in: store) == "'OK'")
        #expect(PointReference.mark(9).name(in: store) == "mark 9")
    }

    @Test("Marks are unknown before a look, expire after two minutes, and are replaced by the next look")
    func store() throws {
        let store = ScreenMarkStore()
        let start = ContinuousClock.now
        #expect(throws: ToolError.self) { try store.mark(1, at: start) }
        store.replace(with: [ScreenMark(number: 1, target: control(.button, "Old", .zero))], at: start)
        #expect(try store.mark(1, at: start + .seconds(119)).target.label == "Old")
        #expect(throws: ToolError.self) { try store.mark(1, at: start + .seconds(121)) }
        #expect(throws: ToolError.self) { try store.mark(2, at: start) }
        store.replace(with: [ScreenMark(number: 1, target: control(.button, "New", .zero))], at: start)
        #expect(try store.mark(1, at: start).target.label == "New")
    }

    @Test("Mouse events use screen points unchanged, and AppKit flips them from the main screen's top")
    func eventAndAppKitPoints() {
        #expect(ScreenCoordinates.eventLocation(for: CGPoint(x: 12, y: 34)) == CGPoint(x: 12, y: 34))
        #expect(ScreenCoordinates.appKitPoint(for: CGPoint(x: 100, y: 200), mainScreenHeight: 900) == CGPoint(x: 100, y: 700))
    }

    @Test("A Vision box maps to screen points and back onto the scaled image with a bottom-left origin")
    func imageAndVisionRects() {
        let area = CGRect(x: 100, y: 50, width: 400, height: 200)
        let screenRect = ScreenCoordinates.screenRect(forNormalized: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), in: area)
        #expect(screenRect == CGRect(x: 200, y: 100, width: 200, height: 50))
        let imageRect = ScreenCoordinates.imageRect(for: screenRect, in: area, imageSize: CGSize(width: 800, height: 400))
        #expect(imageRect == CGRect(x: 200, y: 200, width: 400, height: 100))
    }

    @Test("A drag moves in even steps and ends exactly on its target")
    func dragPath() {
        let path = MouseEvents.path(from: .zero, to: CGPoint(x: 8, y: 4), steps: 4)
        #expect(path == [CGPoint(x: 2, y: 1), CGPoint(x: 4, y: 2), CGPoint(x: 6, y: 3), CGPoint(x: 8, y: 4)])
    }

    @Test("Scrolling up and left use positive wheel deltas")
    func scrollDeltas() {
        #expect(MouseEvents.ScrollDirection.up.lineDeltas == (1, 0))
        #expect(MouseEvents.ScrollDirection.down.lineDeltas == (-1, 0))
        #expect(MouseEvents.ScrollDirection.left.lineDeltas == (0, 1))
        #expect(MouseEvents.ScrollDirection.right.lineDeltas == (0, -1))
    }
}
