# Diagram
The window Macie draws Mermaid diagrams in (flowcharts, sequence, class, state, ER, gantt, mindmap, timeline, pie), for `show_diagram`.

## Files
- `DiagramWindow.swift`: the floating panel: native title bar, closable, resizable, pinch to zoom; sized to the diagram (at most 80% of the screen), centred, shown without taking focus. Each diagram replaces the last.
- `DiagramRenderer.swift`: the offline `WKWebView` that runs the bundled Mermaid; `render(_:dark:)` returns the diagram's natural size or throws Mermaid's syntax error as a `ToolError` so Macie can fix the source and try again.
- `DiagramPage.swift`: the blank page and the render script (strict mode; the neutral theme, or dark when the Mac is).
- `DiagramSource.swift`: drops a Markdown code fence and refuses empty or overlong (over 20,000 characters) source.
- `Vendor/mermaid.min.js`: Mermaid 12.2.0 (MIT, `Vendor/mermaid-LICENSE.txt`), from npm's `mermaid-12.2.0.tgz`, checked against its published integrity `sha512-w7nr/SFrLO7BaVTs3dQTvYSV6nYSBj0Yy9DjBhsIJtAcHqRzXSq4Pg32ujHZ/AdWsAMNEvvhbm5dt9E2tOiHzw==`. File SHA-256: `a8a6a6f805b074a8261a2825c86f99c8054acb3b35f50bb7e24a4f9f2c3c3b9f`.

## Public surface
- `DiagramWindow()`, `show(_ source:title:) async throws -> CGSize`
- `DiagramRenderer(mermaidScript:)`, `DiagramRenderer(bundle:)`, `render(_:dark:) async throws -> CGSize`, `webView`
- `DiagramSource.clean(_:) throws -> String`, `DiagramSource.maximumLength`

## Safety
A diagram is text Macie wrote, possibly from a page or file she read, so it's treated as untrusted:
- Nothing loads: the page's Content-Security-Policy is `default-src 'none'` (inline styles and `data:` images only), there is no base URL, and website data is not kept.
- Nothing runs but Mermaid: it's injected by the app; the page allows no scripts of its own, and Mermaid's strict mode strips handlers and links from labels (tested).
- Nothing navigates: every navigation except the blank page is cancelled.
- No bridge: the page has no message handlers, so it can't reach macobar or the Mac.
- Other AI apps don't get `show_diagram` over MCP, like the other drawing tools.

## Updating Mermaid
Pick a release at least two weeks old, download its tarball from npm, check its `sha512` against `npm view mermaid@<version> dist.integrity`, copy `package/dist/mermaid.min.js` and `package/LICENSE`, update the version and hashes above, and run the tests.

## Tested by
`MacobarTests/DiagramTests.swift`: cleaning; real renders offscreen (a flowchart's size, a syntax error, a label's script not running).

## Depends on
Tools (`ToolError`), WebKit.
