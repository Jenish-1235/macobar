/// Shows a Mermaid diagram in a window, to explain something visually.
struct ShowDiagramTool: Tool {
    /// Where diagrams are shown.
    private let window: DiagramWindow

    /// Name the model calls it by.
    let name = "show_diagram"
    /// When to call it and what it returns.
    let description = """
        Shows a Mermaid diagram in a window when a flow, structure, timeline, plan or comparison is clearer drawn \
        (flowchart, sequenceDiagram, classDiagram, stateDiagram-v2, erDiagram, gantt, mindmap, timeline, pie). Pass \
        Mermaid source without code fences. Returns the size shown, or Mermaid's syntax error to fix and call again. \
        Each call replaces the last diagram.
        """

    /// Creates the tool, showing diagrams in `window`.
    init(window: DiagramWindow) {
        self.window = window
    }

    /// Takes the Mermaid source and a title.
    var parameters: JSONValue {
        Schema.object([
            "mermaid": Schema.string("Mermaid source, e.g. \"flowchart TD\\n  A[Start] --> B{Ready?}\"."),
            "title": Schema.string("Short window title."),
        ], required: ["mermaid"])
    }

    /// Describes the drawing.
    func activity(for input: ToolInput) -> String { "Drawing a diagram" }

    /// Checks the source and shows it.
    func run(_ input: ToolInput) async throws -> String {
        let source = try DiagramSource.clean(input.requiredString("mermaid"))
        let size = try await window.show(source, title: input.string("title") ?? "Diagram")
        return "Showing the diagram in a \(Int(size.width)) × \(Int(size.height)) point window."
    }
}
