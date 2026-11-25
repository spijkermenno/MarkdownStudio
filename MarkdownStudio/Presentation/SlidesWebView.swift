import Observation
import WebKit

enum SlideSeparator: String, CaseIterable, Identifiable {
    case automatic = "auto", rule, heading
    var id: Self { self }
    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .rule: "Horizontal rules (---)"
        case .heading: "Headings (# and ##)"
        }
    }
}

/// State shown in the presenter window.
@Observable
final class PresentationState {
    var index = 0
    var count = 0
    var notes = ""
    var title = ""
    var nextTitle = ""
    var startedAt = Date()
}

/// Loads `Web/slides.html` in a web view and talks to `MDSlides`.
final class SlidesWebView: NSObject, WKScriptMessageHandler {
    let webView: WKWebView
    private let schemeHandler = PreviewSchemeHandler()
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReady = false
    var onSlide: (([String: Any]) -> Void)?
    var onExit: (() -> Void)?

    /// Options for `MDSlides.load`, including the language and title.
    static func options(_ configuration: PreviewConfiguration, separator: SlideSeparator, title: String) -> [String: Any] {
        var options = configuration.javaScriptValue
        options["separator"] = separator.rawValue
        options["lang"] = PreviewController.defaultLanguage
        options["title"] = title
        return options
    }

    init(documentDirectory: URL?) {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: PreviewSchemeHandler.scheme)
        config.preferences.shouldPrintBackgrounds = true
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720), configuration: config)
        super.init()
        schemeHandler.documentDirectory = documentDirectory
        config.userContentController.add(WeakSlidesHandler(self), name: "slides")
        webView.load(URLRequest(url: URL(string: "mdstudio://app/slides.html")!))
    }

    func load(_ markdown: String, options: [String: Any]) async -> Int {
        if !isReady { await withCheckedContinuation { readyWaiters.append($0) } }
        return await withCheckedContinuation { continuation in
            webView.callAsyncJavaScript("return await MDSlides.load(markdown, options)",
                                        arguments: ["markdown": markdown, "options": options],
                                        in: nil, in: .page) { result in
                continuation.resume(returning: (try? result.get()) as? Int ?? 0)
            }
        }
    }

    func run(_ script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            isReady = true
            readyWaiters.forEach { $0.resume() }
            readyWaiters.removeAll()
        case "slide": onSlide?(body)
        case "exit": onExit?()
        default: break
        }
    }
}

private final class WeakSlidesHandler: NSObject, WKScriptMessageHandler {
    weak var target: SlidesWebView?
    init(_ target: SlidesWebView) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
