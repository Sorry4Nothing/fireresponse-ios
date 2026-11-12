import UIKit
import WebKit

/// Zeichnet ein SVG vom Server einmal in ein PNG, weil `UIImage` kein SVG liest (Issue #45). Ohne neue Abhängigkeit: Das System
/// zeichnet es in einer unsichtbaren Web-Ansicht, als Bild in einer Seite ohne Skripte und ohne Netz. Der Server hat das SVG schon bereinigt;
/// die App verlässt sich nicht darauf. Bei einem Fehler oder nach 3 Sekunden gibt es `nil`, und der Ersatz (Kürzel, Platzhalter) bleibt.
@MainActor
enum SVGRasterizer {
    /// Ob die Bytes ein SVG sind (ein PNG beginnt mit «\u{89}PNG»).
    nonisolated static func isSVG(_ data: Data) -> Bool {
        data.prefix(2048).range(of: Data("<svg".utf8)) != nil
    }

    /// PNG in `size` Punkten (mit Bildschirmmass), das SVG eingepasst; `nil`, wenn es sich nicht zeichnen lässt.
    static func png(from svg: Data, size: CGSize) async -> Data? {
        guard isSVG(svg), size.width > 0, size.height > 0 else { return nil }
        let job = Job(size: size)
        // Zeichnen und Schnappschuss laufen in der Web-Ansicht; hängt eine davon (kein Fenster, Systemlast), gibt nach 5 Sekunden der Ersatz den Ausschlag.
        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            let race = Race(continuation)
            Task { race.finish(await job.render(svg)) }
            Task {
                try? await Task.sleep(for: .seconds(5))
                race.finish(nil)
            }
        }
    }

    /// Das Bild für die Anzeige: ein SVG als PNG, alles andere unverändert; scheitert das Zeichnen, bleibt es beim SVG (dann zeigt die Ansicht den Ersatz).
    static func displayable(_ data: Data, size: CGSize) async -> Data {
        guard isSVG(data) else { return data }
        return await png(from: data, size: size) ?? data
    }
}

/// Das erste Ergebnis gilt, jedes weitere fällt weg.
@MainActor
private final class Race {
    private var continuation: CheckedContinuation<Data?, Never>?
    init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }

    func finish(_ data: Data?) {
        continuation?.resume(returning: data)
        continuation = nil
    }
}

@MainActor
private final class Job: NSObject, WKNavigationDelegate {
    private let size: CGSize
    private let webView: WKWebView
    private var continuation: CheckedContinuation<Bool, Never>?

    init(size: CGSize) {
        self.size = size
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
    }

    func render(_ svg: Data) async -> Data? {
        // Eine Web-Ansicht ohne Fenster zeichnet nicht zuverlässig: unsichtbar an das erste Fenster hängen.
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first
        webView.alpha = 0.01
        window?.insertSubview(webView, at: 0)
        defer { webView.removeFromSuperview() }

        let html = """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <style>html,body{margin:0;width:100%;height:100%;background:transparent}img{width:100%;height:100%;object-fit:contain}</style>
        <img src="data:image/svg+xml;base64,\(svg.base64EncodedString())">
        """
        guard await load(html) else { return nil }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(origin: .zero, size: size)
        configuration.snapshotWidth = NSNumber(value: Double(size.width))
        configuration.afterScreenUpdates = true
        return try? await webView.takeSnapshot(configuration: configuration).pngData()
    }

    private func load(_ html: String) async -> Bool {
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.finish(false)
        }
        defer { timeout.cancel() }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    private func finish(_ success: Bool) {
        continuation?.resume(returning: success)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(true) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(false) }

    /// Nichts ausser der eigenen Seite wird geladen.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let scheme = navigationAction.request.url?.scheme?.lowercased()
        return scheme == nil || scheme == "about" || scheme == "data" ? .allow : .cancel
    }
}
