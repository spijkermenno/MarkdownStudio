import AppKit
import WebKit
import os

/// Owns the preview's WKWebView for one document window (or an offscreen
/// export). Talks to `Web/preview.js` through `MDPreview.*` calls and the
/// `bridge` message handler.
final class PreviewController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    private let schemeHandler = PreviewSchemeHandler()
    private let logger = Logger(subsystem: "nl.mennospijker.MarkdownStudio", category: "Preview")

    private(set) var isReady = false
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []
    private var pendingMarkdown: String?
    private var lastMarkdown: String?
    private var configuration = PreviewConfiguration()
    private var configured = false
    private var isRendering = false

    var onScroll: ((_ line: Double, _ atBottom: Bool) -> Void)?
    var onReveal: ((Int) -> Void)?
    var onToggleTask: ((Int) -> Void)?
    /// Opens a linked Markdown document, optionally at a heading anchor.
    var onOpenDocument: ((URL, String?) -> Void)?

    var documentDirectory: URL? {
        get { schemeHandler.documentDirectory }
        set { schemeHandler.documentDirectory = newValue }
    }

    var zoom: Double = 1 {
        didSet { webView.pageZoom = zoom }
    }

    override init() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: PreviewSchemeHandler.scheme)
        config.suppressesIncrementalRendering = false
        config.preferences.isElementFullscreenEnabled = false
        config.preferences.shouldPrintBackgrounds = true
        let contentController = WKUserContentController()
        config.userContentController = contentController
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 800), configuration: config)
        super.init()

        contentController.add(WeakScriptMessageHandler(self), name: "bridge")
        webView.navigationDelegate = self
        webView.allowsMagnification = false
        webView.setValue(false, forKey: "drawsBackground")
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.load(URLRequest(url: PreviewSchemeHandler.pageURL))
    }

    // MARK: - Rendering

    func waitUntilReady() async {
        if isReady { return }
        await withCheckedContinuation { readyWaiters.append($0) }
    }

    func configure(_ configuration: PreviewConfiguration) {
        guard !configured || configuration != self.configuration else { return }
        self.configuration = configuration
        configured = true
        guard isReady else { return }
        Task { await self.call("return await MDPreview.configure(options)", ["options": configuration.javaScriptValue]) }
    }

    /// Renders `markdown`. Calls are coalesced: while a render is in flight only
    /// the latest text is kept.
    func render(_ markdown: String) {
        pendingMarkdown = markdown
        guard isReady, !isRendering else { return }
        Task { await self.flush() }
    }

    /// Renders and waits until diagrams, math and images have finished.
    func renderAndWait(_ markdown: String) async {
        await waitUntilReady()
        pendingMarkdown = markdown
        await flush()
        while isRendering { try? await Task.sleep(for: .milliseconds(20)) }
    }

    private func flush() async {
        guard !isRendering else { return }
        isRendering = true
        while let markdown = pendingMarkdown {
            pendingMarkdown = nil
            lastMarkdown = markdown
            await call("return await MDPreview.render(markdown)", ["markdown": markdown])
        }
        isRendering = false
    }

    func scroll(toLine line: Double, atBottom: Bool) {
        guard isReady else { return }
        webView.evaluateJavaScript("MDPreview.scrollToLine(\(line.isFinite ? line : 0), \(atBottom))", completionHandler: nil)
    }

    func reveal(line: Int) {
        guard isReady else { return }
        webView.evaluateJavaScript("MDPreview.revealLine(\(line))", completionHandler: nil)
    }

    /// Converts clipboard HTML to Markdown (Turndown, see Web/paste.js).
    func markdown(fromHTML html: String) async -> String? {
        await waitUntilReady()
        return await call("return MDPaste.convert(html)", ["html": html])
    }

    /// The rendered body HTML with preview-only markup removed.
    func exportedBodyHTML() async -> String {
        await call("return MDPreview.exportHTML()") ?? ""
    }

    /// Runs `body` as an async JavaScript function; returns string results.
    @discardableResult
    private func call(_ body: String, _ arguments: [String: Any] = [:]) async -> String? {
        await withCheckedContinuation { continuation in
            webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { [logger] result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value as? String)
                case .failure(let error):
                    logger.error("JavaScript error: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            pageDidLoad()
        case "scroll":
            onScroll?((body["line"] as? Double) ?? 0, (body["atBottom"] as? Bool) ?? false)
        case "reveal":
            if let line = body["line"] as? Int { onReveal?(line) }
        case "toggleTask":
            if let line = body["line"] as? Int { onToggleTask?(line) }
        case "copy":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body["text"] as? String ?? "", forType: .string)
        case "log":
            let text = body["message"] as? String ?? ""
            if body["level"] as? String == "error" {
                logger.error("\(text, privacy: .public)")
            } else {
                logger.debug("\(text, privacy: .public)")
            }
        default:
            break
        }
    }

    private func pageDidLoad() {
        isReady = true
        Task {
            await self.call("return await MDPreview.configure(options)", ["options": configuration.javaScriptValue])
            await self.flush()
            let waiters = self.readyWaiters
            self.readyWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if url == PreviewSchemeHandler.pageURL && action.navigationType != .linkActivated { return .allow }
        if action.targetFrame?.isMainFrame == false && url.scheme == PreviewSchemeHandler.scheme { return .allow }

        if let fileURL = schemeHandler.fileURL(for: url) {
            let isMarkdown = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "txt"].contains(fileURL.pathExtension.lowercased())
            if isMarkdown, let onOpenDocument {
                onOpenDocument(fileURL, PreviewSchemeHandler.fragment(in: url))
            } else {
                NSWorkspace.shared.open(fileURL)
            }
        } else if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "ftp", "tel"].contains(scheme) {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Reload and re-render if the web content process crashes.
        isReady = false
        isRendering = false
        pendingMarkdown = pendingMarkdown ?? lastMarkdown
        webView.load(URLRequest(url: PreviewSchemeHandler.pageURL))
    }
}

/// Breaks the retain cycle between WKUserContentController and its handler.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
