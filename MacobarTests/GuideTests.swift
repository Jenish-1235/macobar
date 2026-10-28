import CoreGraphics
import Testing

/// Verifies guide mode's pure logic: click hit-testing, argument parsing and timeouts.
struct GuideTests {
    /// Height of the pretend main display, in points.
    private static let primaryScreenHeight: CGFloat = 1_000
    /// A target near the top-left of the main display, in top-left-origin points.
    private static let area = CGRect(x: 100, y: 100, width: 50, height: 20)

    @Test("A click near the top of the screen in AppKit points lands in a top-left-origin area there")
    func clickInsideArea() {
        #expect(UserProgressWaiter.isClick(at: CGPoint(x: 110, y: 890), inside: Self.area, primaryScreenHeight: Self.primaryScreenHeight))
    }

    @Test("A click at the same raw numbers without flipping misses the area")
    func clickUnflippedMisses() {
        #expect(!UserProgressWaiter.isClick(at: CGPoint(x: 110, y: 110), inside: Self.area, primaryScreenHeight: Self.primaryScreenHeight))
    }

    @Test("A click on a display above the main one hits an area with a negative y")
    func clickOnDisplayAbove() {
        let area = CGRect(x: 0, y: -500, width: 100, height: 100)
        #expect(UserProgressWaiter.isClick(at: CGPoint(x: 50, y: 1_450), inside: area, primaryScreenHeight: Self.primaryScreenHeight))
    }

    @Test("click_in reads its rect")
    func parsesClickIn() throws {
        let input = ToolInput(["expect": "click_in", "rect": ["x": 10, "y": 20, "width": 30, "height": 40]])
        #expect(try WaitForUserTool.expectation(from: input) == .clickIn(CGRect(x: 10, y: 20, width: 30, height: 40)))
    }

    @Test("click_in without a rect, or with an empty one, is refused")
    func refusesMissingOrEmptyRect() {
        #expect(throws: ToolError.self) { try WaitForUserTool.expectation(from: ToolInput(["expect": "click_in"])) }
        let empty = ToolInput(["expect": "click_in", "rect": ["x": 10, "y": 20, "width": 0, "height": 40]])
        #expect(throws: ToolError.self) { try WaitForUserTool.expectation(from: empty) }
    }

    @Test("text_appears needs text and keeps it")
    func parsesTextAppears() throws {
        #expect(throws: ToolError.self) { try WaitForUserTool.expectation(from: ToolInput(["expect": "text_appears"])) }
        let input = ToolInput(["expect": "text_appears", "text": " Saved "])
        #expect(try WaitForUserTool.expectation(from: input) == .textAppears("Saved"))
    }

    @Test("Expectations without arguments parse by name")
    func parsesSimpleExpectations() throws {
        let expected: [String: UserExpectation] = [
            "app_change": .appChange, "window_change": .windowChange, "menu_open": .menuOpen, "any_key": .anyKey,
        ]
        for (name, expectation) in expected {
            #expect(try WaitForUserTool.expectation(from: ToolInput(["expect": .string(name)])) == expectation)
        }
    }

    @Test("An unknown or missing expect is refused")
    func refusesUnknownExpect() {
        #expect(throws: ToolError.self) { try WaitForUserTool.expectation(from: ToolInput(["expect": "double_click"])) }
        #expect(throws: ToolError.self) { try WaitForUserTool.expectation(from: ToolInput()) }
    }

    @Test("Timeouts default to 60 seconds and stay between 1 and 300")
    func clampsTimeout() {
        #expect(UserProgressWaiter.timeout(seconds: nil).components.seconds == 60)
        #expect(UserProgressWaiter.timeout(seconds: 90).components.seconds == 90)
        #expect(UserProgressWaiter.timeout(seconds: 0).components.seconds == 1)
        #expect(UserProgressWaiter.timeout(seconds: 1_000).components.seconds == 300)
    }
}
