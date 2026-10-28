import Testing

/// Verifies that page scripts inject arguments only as JSON literals.
struct BrowserToolsTests {
    /// Text that would break out of a naively quoted JavaScript string.
    static let hostileText = "a\"b'c\\d\ne</script>`${x}`); alert(1); //"

    @Test("A literal decodes back to the exact text")
    func literalRoundTrips() throws {
        #expect(try JSONValue.parse(PageScript.literal(Self.hostileText)) == .string(Self.hostileText))
    }

    @Test("A literal keeps quotes, backslashes and newlines escaped")
    func literalEscapes() {
        let literal = PageScript.literal(Self.hostileText)
        #expect(literal.hasPrefix("\"") && literal.hasSuffix("\""))
        #expect(!literal.contains("\n"))
        #expect(literal.contains(#"a\"b"#))
        #expect(literal.contains(#"c\\d"#))
        #expect(literal.contains(#"\n"#))
    }

    @Test("Clicking by text passes the text as a literal")
    func clickByText() {
        #expect(PageScript.click(text: Self.hostileText).contains("controlNamed(\(PageScript.literal(Self.hostileText)))"))
    }

    @Test("Clicking by index passes a bare number")
    func clickByIndex() {
        #expect(PageScript.click(index: 7).contains("controlAt(7)"))
    }

    @Test("Filling passes the index and value as literals")
    func fill() {
        let script = PageScript.fill(index: 3, value: Self.hostileText)
        #expect(script.contains("const index = 3;"))
        #expect(script.contains("let value = \(PageScript.literal(Self.hostileText));"))
    }

    @Test("A model script is evaluated from a literal, never spliced in")
    func evaluate() {
        let script = PageScript.evaluate(Self.hostileText)
        #expect(script.contains("(0, eval)(\(PageScript.literal(Self.hostileText)))"))
        #expect(!script.contains(Self.hostileText))
    }

    @Test("Reading the page uses the given limits")
    func readPage() {
        let script = PageScript.readPage(textLimit: 15_000, controlLimit: 200)
        #expect(script.contains("text.slice(0, 15000)"))
        #expect(script.contains("found.slice(0, 200)"))
    }

    @Test("Every script reports its value or error as JSON")
    func envelope() {
        for script in [PageScript.readPage(textLimit: 1, controlLimit: 1), PageScript.click(index: 1), PageScript.evaluate("1")] {
            #expect(script.hasPrefix("(() => {"))
            #expect(script.hasSuffix("})()"))
            #expect(script.contains("JSON.stringify({ value:"))
            #expect(script.contains("JSON.stringify({ error:"))
        }
    }
}
