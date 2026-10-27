import CoreGraphics
import Testing

/// Verifies how the chat bar's gap is found among Dock items.
struct DockGeometryTests {
    /// A Dock frame used by every test.
    private let dockFrame = CGRect(x: 0, y: 0, width: 400, height: 44)

    /// Builds a 32-point-wide item at slot `index`.
    private func item(_ index: Int, isSpacer: Bool) -> DockItem {
        DockItem(isSpacer: isSpacer, frame: CGRect(x: CGFloat(index) * 32, y: 0, width: 32, height: 44))
    }

    @Test("Gap spans the spacer run right after Finder")
    func findsGapAfterFirstItem() throws {
        let items = [item(0, isSpacer: false), item(1, isSpacer: true), item(2, isSpacer: true), item(3, isSpacer: false)]
        let geometry = try #require(DockGeometry(dockFrame: dockFrame, items: items))
        #expect(geometry.gapFrame == CGRect(x: 32, y: 0, width: 64, height: 44))
    }

    @Test("No gap when Finder is followed by an app")
    func noGapWithoutLeadingSpacers() {
        let items = [item(0, isSpacer: false), item(1, isSpacer: false), item(2, isSpacer: true)]
        #expect(DockGeometry(dockFrame: dockFrame, items: items) == nil)
    }

    @Test("Converts Accessibility coordinates to AppKit coordinates")
    func flipsVertically() {
        let accessibilityRect = CGRect(x: 10, y: 1068, width: 32, height: 44)
        #expect(accessibilityRect.flippedVertically(withinHeight: 1117) == CGRect(x: 10, y: 5, width: 32, height: 44))
    }
}
