import Testing

/// Verifies how streamed replies are cut into sentences and cleaned before they're read aloud.
struct SpeechTests {
    /// Every sentence `fragments` produce when streamed in order, including what's left at the end.
    private func sentences(_ fragments: String...) -> [String] {
        var splitter = SentenceSplitter()
        let completed = fragments.flatMap { splitter.append($0) }
        return completed + (splitter.finish().map { [$0] } ?? [])
    }

    @Test("Splits after full stops, exclamation and question marks")
    func splitsOnTerminators() {
        #expect(sentences("Hello there. Really?! How are you?") == ["Hello there.", "Really?!", "How are you?"])
    }

    @Test("Hands over each sentence as soon as it's complete")
    func streamsSentences() {
        var splitter = SentenceSplitter()
        #expect(splitter.append("Hel") == [])
        #expect(splitter.append("lo. Wo") == ["Hello."])
        #expect(splitter.append("rld! Bye") == ["World!"])
        #expect(splitter.finish() == "Bye")
    }

    @Test("Waits to see what follows a full stop at the end of the text")
    func waitsAfterTrailingStop() {
        var splitter = SentenceSplitter()
        #expect(splitter.append("Done.") == [])
        #expect(splitter.append(" Next") == ["Done."])
    }

    @Test("Splits on new lines")
    func splitsOnNewlines() {
        #expect(sentences("First line\nSecond line\n") == ["First line", "Second line"])
    }

    @Test("Doesn't split after e.g. or Mr.")
    func keepsAbbreviations() {
        #expect(sentences("Use an app, e.g. Safari, to browse. Ask Mr. Smith today.") == ["Use an app, e.g. Safari, to browse.", "Ask Mr. Smith today."])
    }

    @Test("Doesn't split inside decimals, URLs or words with an ellipsis")
    func keepsDotsInsideWords() {
        #expect(sentences("It is 3.5 degrees. Open https://example.com/a.b?c=1 now. Wait...what happened?") == [
            "It is 3.5 degrees.", "Open https://example.com/a.b?c=1 now.", "Wait...what happened?",
        ])
    }

    @Test("Keeps closing quotes with their sentence")
    func keepsClosingQuotes() {
        #expect(sentences("She said \"hi.\" Then left.") == ["She said \"hi.\"", "Then left."])
        #expect(sentences("**Done.** __Next.__ Last") == ["**Done.**", "__Next.__", "Last"])
    }

    @Test("Doesn't split after a list number")
    func keepsListNumbers() {
        #expect(sentences("1. Open Safari\n2. Go home") == ["1. Open Safari", "2. Go home"])
    }

    @Test("Keeps a code block whole")
    func keepsCodeBlocksWhole() {
        #expect(sentences("Run this:\n```\nls -la. Now\n```\nDone. ") == ["Run this:", "```\nls -la. Now\n```", "Done."])
    }

    @Test("Holds an open code block until the reply ends")
    func holdsOpenCodeBlock() {
        var splitter = SentenceSplitter()
        #expect(splitter.append("Here:\n```\nlet x = 1.\n") == ["Here:"])
        #expect(splitter.finish() == "```\nlet x = 1.")
    }

    @Test("Says links as \"link\"")
    func saysLinks() {
        #expect(SpeakableText.from("Open https://example.com/page for details.") == "Open link for details.")
        #expect(SpeakableText.from("Visit https://example.com.") == "Visit link.")
        #expect(SpeakableText.from("www.apple.com has it") == "link has it")
    }

    @Test("Reads a Markdown link's text, not its address")
    func readsLinkText() {
        #expect(SpeakableText.from("See [the docs](https://example.com) now.") == "See the docs now.")
    }

    @Test("Skips code blocks, open or closed")
    func skipsCode() {
        #expect(SpeakableText.from("```swift\nlet x = 1\n```") == "")
        #expect(SpeakableText.from("```swift\nlet x") == "")
    }

    @Test("Drops Markdown symbols but keeps the words")
    func dropsMarkdown() {
        #expect(SpeakableText.from("## Summary") == "Summary")
        #expect(SpeakableText.from("- **Bold** item") == "Bold item")
        #expect(SpeakableText.from("> Quoted line") == "Quoted line")
        #expect(SpeakableText.from("Run `ls -la` here") == "Run ls -la here")
        #expect(SpeakableText.from("take_screenshot works") == "take_screenshot works")
    }

    @Test("Skips text with nothing to say")
    func skipsSymbolsOnly() {
        #expect(SpeakableText.from("---") == "")
    }
}
