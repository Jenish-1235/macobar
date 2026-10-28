import CoreGraphics
import Foundation
import Testing

/// Verifies how drawings move from the model's top-left screen points into each screen's view space.
struct OverlayCoordinatesTests {
    @Test("A top-left point on the main screen flips into AppKit's bottom-left space")
    func topLeftToAppKit() {
        #expect(OverlayCoordinates.appKitPoint(fromTopLeft: CGPoint(x: 100, y: 50), mainScreenHeight: 1000) == CGPoint(x: 100, y: 950))
    }

    @Test("An AppKit point lands at the same spot in the main screen's view space")
    func appKitToMainScreenView() {
        let mainScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(OverlayCoordinates.viewPoint(fromAppKit: CGPoint(x: 100, y: 932), in: mainScreen) == CGPoint(x: 100, y: 50))
    }

    @Test("An AppKit point is measured from the top-left corner of a second screen")
    func appKitToSecondScreenView() {
        let secondScreen = CGRect(x: 1512, y: 200, width: 1920, height: 1080)
        #expect(OverlayCoordinates.viewPoint(fromAppKit: CGPoint(x: 1600, y: 1000), in: secondScreen) == CGPoint(x: 88, y: 280))
    }

    @Test("A rect stays upright through the vertical flip")
    func rectFlip() {
        let shape = OverlayShape.highlight(CGRect(x: 100, y: 50, width: 200, height: 40))
        let flipped = shape.mapped { OverlayCoordinates.appKitPoint(fromTopLeft: $0, mainScreenHeight: 1000) }
        #expect(flipped == .highlight(CGRect(x: 100, y: 910, width: 200, height: 40)))
    }

    @Test("A top-left rect on the main screen comes back unchanged in its view space")
    func roundTrip() {
        let mainScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let shape = OverlayShape.arrow(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 300, y: 400))
        let onScreen = shape
            .mapped { OverlayCoordinates.appKitPoint(fromTopLeft: $0, mainScreenHeight: mainScreen.height) }
            .mapped { OverlayCoordinates.viewPoint(fromAppKit: $0, in: mainScreen) }
        #expect(onScreen == shape)
    }
}

/// Verifies how draw_on_screen's arguments are checked and read.
struct DrawingRequestTests {
    /// A request built from `json` arguments.
    private func request(_ json: String) throws -> DrawingRequest {
        try DrawingRequest(arguments: JSONValue.parse(json).object ?? [:])
    }

    /// The message `json` arguments are refused with, or nil when they're accepted.
    private func refusal(_ json: String) -> String? {
        do {
            _ = try request(json)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @Test("Reads every kind of shape and defaults to six seconds")
    func readsEveryKind() throws {
        let drawing = try request("""
            {"shapes": [
              {"kind": "highlight", "rect": {"x": 1, "y": 2, "width": 3, "height": 4}},
              {"kind": "circle", "rect": {"x": 5, "y": 6, "width": 7, "height": 8}},
              {"kind": "arrow", "from": {"x": 0, "y": 0}, "to": {"x": 9, "y": 9}},
              {"kind": "label", "point": {"x": 10, "y": 11}, "text": "  Click here  "},
              {"kind": "path", "points": [{"x": 0, "y": 0}, {"x": 1, "y": 1}]},
              {"kind": "spotlight", "rect": {"x": 0, "y": 0, "width": 50, "height": 50}},
              {"kind": "pointer", "point": {"x": 12, "y": 13}}
            ]}
            """)
        #expect(drawing.shapes == [
            .highlight(CGRect(x: 1, y: 2, width: 3, height: 4)),
            .circle(CGRect(x: 5, y: 6, width: 7, height: 8)),
            .arrow(from: .zero, to: CGPoint(x: 9, y: 9)),
            .label("Click here", at: CGPoint(x: 10, y: 11)),
            .path([.zero, CGPoint(x: 1, y: 1)]),
            .spotlight(CGRect(x: 0, y: 0, width: 50, height: 50)),
            .pointer(CGPoint(x: 12, y: 13)),
        ])
        #expect(drawing.duration == .seconds(6))
    }

    @Test("Takes the duration in seconds")
    func readsDuration() throws {
        let drawing = try request(#"{"shapes": [{"kind": "pointer", "point": {"x": 1, "y": 1}}], "duration": 2.5}"#)
        #expect(drawing.duration == .milliseconds(2500))
    }

    @Test("Accepts shapes sent as a JSON string")
    func readsShapesString() throws {
        let drawing = try request(#"{"shapes": "[{\"kind\": \"pointer\", \"point\": {\"x\": 1, \"y\": 2}}]"}"#)
        #expect(drawing.shapes == [.pointer(CGPoint(x: 1, y: 2))])
    }

    @Test("Refuses a request with no shapes")
    func refusesNoShapes() {
        #expect(refusal(#"{"shapes": []}"#)?.contains("at least one shape") == true)
        #expect(refusal("{}")?.contains("must be an array") == true)
    }

    @Test("Refuses more than twenty shapes")
    func refusesTooManyShapes() {
        let shapes = Array(repeating: #"{"kind": "pointer", "point": {"x": 1, "y": 1}}"#, count: 21).joined(separator: ",")
        #expect(refusal(#"{"shapes": [\#(shapes)]}"#)?.contains("at most 20 shapes") == true)
    }

    @Test("Names the shape and lists the kinds when a kind is unknown")
    func refusesUnknownKind() {
        let message = refusal(#"{"shapes": [{"kind": "pointer", "point": {"x": 1, "y": 1}}, {"kind": "star"}]}"#)
        #expect(message?.hasPrefix("Shape 2: unknown kind \"star\"") == true)
        #expect(message?.contains("highlight, circle, arrow, label, path, spotlight, pointer") == true)
    }

    @Test("Refuses shapes missing the fields their kind needs")
    func refusesMissingFields() {
        #expect(refusal(#"{"shapes": [{"kind": "highlight"}]}"#)?.contains("\"rect\" must be an object") == true)
        #expect(refusal(#"{"shapes": [{"kind": "arrow", "from": {"x": 1, "y": 1}}]}"#)?.contains("\"to\" must be an object") == true)
        #expect(refusal(#"{"shapes": [{"kind": "label", "point": {"x": 1, "y": 1}, "text": "  "}]}"#)?.contains("needs \"text\"") == true)
        #expect(refusal(#"{"shapes": [{"kind": "path", "points": [{"x": 1, "y": 1}]}]}"#)?.contains("at least two") == true)
    }

    @Test("Refuses empty rects and long labels")
    func refusesBadValues() {
        #expect(refusal(#"{"shapes": [{"kind": "circle", "rect": {"x": 0, "y": 0, "width": 0, "height": 10}}]}"#)?.contains("above 0") == true)
        let longText = String(repeating: "a", count: 81)
        #expect(refusal(#"{"shapes": [{"kind": "label", "point": {"x": 1, "y": 1}, "text": "\#(longText)"}]}"#)?.contains("80 characters") == true)
    }

    @Test("Refuses durations outside 0 to 60 seconds")
    func refusesBadDuration() {
        let pointer = #"{"kind": "pointer", "point": {"x": 1, "y": 1}}"#
        #expect(refusal(#"{"shapes": [\#(pointer)], "duration": 0}"#)?.contains("at most 60 seconds") == true)
        #expect(refusal(#"{"shapes": [\#(pointer)], "duration": 61}"#)?.contains("at most 60 seconds") == true)
        #expect(refusal(#"{"shapes": [\#(pointer)], "duration": 60}"#) == nil)
    }
}
