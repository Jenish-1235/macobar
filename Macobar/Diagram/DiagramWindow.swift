import AppKit

/// The floating window Macie shows diagrams in: a native title bar, resizable, pinch to zoom, above other windows without taking focus.
@MainActor
final class DiagramWindow {
    /// Room around the diagram: the page's padding on both sides.
    private static let padding: CGFloat = 48
    /// Smallest content size, so a tiny diagram still reads as a window.
    private static let minimumSize = CGSize(width: 360, height: 240)
    /// Largest share of the screen a diagram opens at; it scales down to fit and can be zoomed.
    private static let screenShare: CGFloat = 0.8

    /// The panel, made on first use.
    private var panel: NSPanel?
    /// Draws into the panel, made on first use.
    private var renderer: DiagramRenderer?

    /// Draws `source` titled `title`, replacing any diagram shown, and returns the window's content size.
    func show(_ source: String, title: String) async throws -> CGSize {
        let renderer = try self.renderer ?? makeRenderer()
        let panel = self.panel ?? makePanel(showing: renderer.webView)
        let natural = try await renderer.render(source, dark: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        let size = fittedSize(for: natural, on: panel.screen ?? NSScreen.main)
        panel.title = title
        panel.setContentSize(size)
        panel.center()
        panel.orderFrontRegardless()
        return size
    }

    /// Loads the bundled Mermaid.
    private func makeRenderer() throws -> DiagramRenderer {
        guard let renderer = DiagramRenderer(bundle: .main) else { throw ToolError("macobar's copy of Mermaid is missing.") }
        self.renderer = renderer
        return renderer
    }

    /// A titled, closable, resizable panel that floats on the current Space without activating macobar.
    private func makePanel(showing view: NSView) -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.minimumSize),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentMinSize = Self.minimumSize
        panel.contentView = view
        self.panel = panel
        return panel
    }

    /// The diagram's natural size plus padding, kept between the minimum and a share of the screen.
    private func fittedSize(for natural: CGSize, on screen: NSScreen?) -> CGSize {
        let limit = screen?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(
            width: min(max(natural.width + Self.padding, Self.minimumSize.width), limit.width * Self.screenShare),
            height: min(max(natural.height + Self.padding, Self.minimumSize.height), limit.height * Self.screenShare)
        )
    }
}
