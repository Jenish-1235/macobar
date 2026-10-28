import Foundation
import WebKit

/// Draws Mermaid diagrams in an offline web view: only the bundled Mermaid runs, nothing loads from the network, and nothing navigates away.
@MainActor
final class DiagramRenderer: NSObject, WKNavigationDelegate {
    /// The only address the view may show: the blank page it starts on.
    private static let blankPage = "about:blank"

    /// The view showing the latest diagram.
    let webView: WKWebView
    /// Whether the blank page has loaded with Mermaid in it.
    private var isPageLoaded = false
    /// Renders waiting for the page to load.
    private var pageWaiters: [CheckedContinuation<Void, Never>] = []

    /// Creates a renderer running `mermaidScript`, Mermaid's browser bundle.
    init(mermaidScript: String) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(
            WKUserScript(source: mermaidScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsMagnification = true
        webView.loadHTMLString(DiagramPage.html, baseURL: nil)
    }

    /// A renderer using the Mermaid bundled in `bundle`, or nil when it's missing.
    convenience init?(bundle: Bundle) {
        guard let url = bundle.url(forResource: "mermaid.min", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        self.init(mermaidScript: script)
    }

    /// Draws `source` and returns its natural size; Mermaid's syntax error comes back as a `ToolError` so Macie can fix the source.
    func render(_ source: String, dark: Bool) async throws -> CGSize {
        await waitForPage()
        let result: Any?
        do {
            result = try await webView.callAsyncJavaScript(
                DiagramPage.renderScript,
                arguments: ["source": source, "dark": dark, "maxLength": DiagramSource.maximumLength],
                contentWorld: .page
            )
        } catch let error as NSError where error.domain == WKError.errorDomain {
            let message = error.userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
            throw ToolError("Mermaid couldn't draw it: \(message)")
        }
        guard let size = result as? [Double], size.count == 2 else { throw ToolError("The diagram didn't draw.") }
        return CGSize(width: size[0], height: size[1])
    }

    /// Returns once the blank page has loaded.
    private func waitForPage() async {
        guard !isPageLoaded else { return }
        await withCheckedContinuation { pageWaiters.append($0) }
    }

    /// Allows only the blank page, so a diagram can never open a link or load anything.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.request.url?.absoluteString == Self.blankPage ? .allow : .cancel
    }

    /// Lets waiting renders go ahead.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageLoaded = true
        pageWaiters.forEach { $0.resume() }
        pageWaiters.removeAll()
    }

    /// Starts over with a fresh page when the web content process quits.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isPageLoaded = false
        webView.loadHTMLString(DiagramPage.html, baseURL: nil)
    }
}
