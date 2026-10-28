import Foundation
import Testing

/// Verifies how Mermaid source is cleaned before it's drawn.
struct DiagramSourceTests {
    @Test("A Markdown code fence and surrounding blank lines are dropped")
    func dropsFence() throws {
        #expect(try DiagramSource.clean("\n```mermaid\nflowchart TD\n  A --> B\n```\n") == "flowchart TD\n  A --> B")
    }

    @Test("Empty or overlong source is refused with a reason the model can act on")
    func refusesEmptyAndOverlong() {
        #expect(throws: ToolError.self) { try DiagramSource.clean("```\n```") }
        #expect(throws: ToolError.self) { try DiagramSource.clean("flowchart TD\n" + String(repeating: "A-->B\n", count: 5_000)) }
    }
}

/// Draws real diagrams with the Mermaid bundled in the app, offscreen.
@MainActor
struct DiagramRendererTests {
    /// A renderer running the app's copy of Mermaid, read from the source tree.
    private func makeRenderer() throws -> DiagramRenderer {
        let script = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Macobar/Diagram/Vendor/mermaid.min.js")
        return DiagramRenderer(mermaidScript: try String(contentsOf: script, encoding: .utf8))
    }

    @Test("A flowchart draws and reports its natural size")
    func drawsFlowchart() async throws {
        let size = try await makeRenderer().render("flowchart LR\n  A[Ask Macie] --> B{Needs you?}\n  B -->|yes| C[Card rises]\n  B -->|no| D[Works quietly]", dark: false)
        #expect(size.width > 100)
        #expect(size.height > 20)
    }

    @Test("A syntax error comes back as Mermaid's message")
    func reportsSyntaxError() async throws {
        await #expect(throws: ToolError.self) {
            try await makeRenderer().render("flowchart TD\n  A -->", dark: true)
        }
    }

    @Test("Script in a label never runs: Mermaid strips handlers and the page allows no scripts of its own")
    func labelScriptNeverRuns() async throws {
        let renderer = try makeRenderer()
        _ = try await renderer.render("flowchart TD\n  A[\"<img src=x onerror=document.title='ran'>\"] --> B", dark: false)
        let title = try await renderer.webView.evaluateJavaScript("document.title") as? String
        let handlers = try await renderer.webView.evaluateJavaScript("document.querySelectorAll('[onerror]').length") as? Int
        #expect(title != "ran")
        #expect(handlers == 0)
    }
}
