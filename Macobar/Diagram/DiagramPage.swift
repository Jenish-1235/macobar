/// The page diagrams are drawn on, and the script that draws one.
enum DiagramPage {
    /// A blank page whose Content-Security-Policy blocks every load and every script of its own (Mermaid comes only from the app), styled to fit the diagram to the window.
    static let html = """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:">
        <style>
        :root { color-scheme: light dark; }
        html, body { margin: 0; height: 100%; background: Canvas; }
        #diagram { box-sizing: border-box; height: 100%; padding: 24px; display: flex; align-items: center; justify-content: center; }
        #diagram svg { width: 100%; height: 100%; }
        </style>
        </head>
        <body><div id="diagram"></div></body>
        </html>
        """

    /// Draws `source` with Mermaid in strict mode (label markup is sanitised: no scripts, event handlers or clickable links) in the neutral theme, or dark to match the Mac, and returns its natural [width, height]; a syntax error is thrown with Mermaid's message.
    static let renderScript = """
        mermaid.initialize({
            startOnLoad: false, securityLevel: "strict", theme: dark ? "dark" : "neutral",
            fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif", maxTextSize: maxLength,
        });
        await mermaid.parse(source);
        const { svg } = await mermaid.render("macie-diagram", source);
        const holder = document.getElementById("diagram");
        holder.innerHTML = svg;
        const box = holder.querySelector("svg").viewBox.baseVal;
        return [box.width, box.height];
        """
}
