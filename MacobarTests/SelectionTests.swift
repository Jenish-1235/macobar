import AppKit
import Testing

/// Verifies replace_selection's arguments and the clipboard copy it restores after pasting.
struct SelectionTests {
    /// A rich-text type alongside plain text, as a copy from a word processor carries.
    private static let richText = NSPasteboard.PasteboardType.rtf

    @Test("A snapshot keeps every type of every item, in order")
    func snapshotKeepsItems() {
        let first = NSPasteboardItem()
        first.setData(Data("Hello".utf8), forType: .string)
        first.setData(Data([1, 2, 3]), forType: Self.richText)
        let second = NSPasteboardItem()
        second.setData(Data("World".utf8), forType: .string)
        #expect(Self.contents(of: PasteboardSnapshot([first, second])) == [
            [.string: Data("Hello".utf8), Self.richText: Data([1, 2, 3])],
            [.string: Data("World".utf8)],
        ])
    }

    @Test("Items rebuilt from a snapshot hold the same data")
    func snapshotRoundTrips() {
        let item = NSPasteboardItem()
        item.setData(Data("Hello".utf8), forType: .string)
        item.setData(Data([1, 2, 3]), forType: Self.richText)
        let snapshot = PasteboardSnapshot([item])
        #expect(Self.contents(of: PasteboardSnapshot(snapshot.pasteboardItems)) == Self.contents(of: snapshot))
    }

    @Test("An empty clipboard makes an empty snapshot")
    func emptySnapshot() {
        #expect(PasteboardSnapshot([]).pasteboardItems.isEmpty)
    }

    @Test("The tool asks once and names the target app")
    func riskAndActivity() {
        let tool = ReplaceSelectionTool()
        #expect(tool.name == "replace_selection")
        #expect(tool.risk(for: ToolInput()) == .confirmOnce)
        #expect(tool.activity(for: ToolInput()) == "Replacing the selected text in the front app")
        #expect(tool.activity(for: ToolInput(["app": "Notes"])) == "Replacing the selected text in Notes")
    }

    @Test("The approval shows the replacement text on one line")
    func activityShowsText() {
        let input = ToolInput(["app": "Notes", "text": "Hi\nthere"])
        #expect(ReplaceSelectionTool().activity(for: input) == "Replacing the selected text in Notes with “Hi ⏎ there”")
    }

    @Test("Long text is cut short in approval prompts")
    func previewIsShort() {
        let preview = approvalPreview(of: String(repeating: "a", count: 200))
        #expect(preview == "“" + String(repeating: "a", count: 79) + "…” (200 characters)")
        #expect(approvalPreview(of: "Send") == "“Send”")
        #expect(approvalPreview(of: "pay \u{202E}txt.exe") == "“pay txt.exe”")
    }

    @Test("Approval prompts show a trailing Return and drop invisible padding")
    func previewShowsHiddenParts() {
        #expect(approvalPreview(of: "Send\n") == "“Send ⏎ ”")
        #expect(approvalPreview(of: "Hi" + String(repeating: "\u{200B}", count: 100) + " rm") == "“Hi rm”")
    }

    @Test("Text is required and the app is optional")
    func parameters() {
        #expect(ReplaceSelectionTool().parameters["required"] == ["text"])
    }

    @Test("Missing or empty text fails before anything is touched")
    func missingText() async {
        await #expect(throws: ToolError.self) { try await ReplaceSelectionTool().run(ToolInput()) }
        await #expect(throws: ToolError.self) { try await ReplaceSelectionTool().run(ToolInput(["text": ""])) }
    }

    /// Each item's data by type, so comparisons don't depend on the order of types within an item.
    private static func contents(of snapshot: PasteboardSnapshot) -> [[NSPasteboard.PasteboardType: Data]] {
        snapshot.items.map { representations in
            Dictionary(representations.map { ($0.type, $0.data) }) { first, _ in first }
        }
    }
}
