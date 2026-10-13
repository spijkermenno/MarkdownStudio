import AppKit
import UniformTypeIdentifiers
import WebKit

/// HTML / PDF export, printing and rich copy. Everything is rendered in a
/// dedicated offscreen preview with a light appearance, so output doesn't
/// depend on the window's view mode or dark mode.
enum ExportService {
    struct Source {
        var markdown: String
        var title: String
        var documentURL: URL?
        var configuration: PreviewConfiguration
        var window: NSWindow?
    }

    // MARK: - Actions

    static func exportHTML(_ source: Source) async {
        guard let url = await savePanel(for: source, type: .html, extension: "html") else { return }
        let html = await standaloneHTML(source)
        do {
            try Data(html.utf8).write(to: url)
        } catch {
            present(error, in: source.window)
        }
    }

    static func exportPDF(_ source: Source) async {
        guard let url = await savePanel(for: source, type: .pdf, extension: "pdf") else { return }
        let renderer = await OffscreenRenderer.render(source)
        let info = printInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        await renderer.print(info: info, showPanels: false, title: source.title, hostWindow: source.window)
        renderer.close()
    }

    static func print(_ source: Source) async {
        let renderer = await OffscreenRenderer.render(source)
        await renderer.print(info: printInfo(), showPanels: true, title: source.title, hostWindow: source.window)
        renderer.close()
    }

    static func copyHTML(_ source: Source) async {
        let body = await renderedBody(source)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(body, forType: .html)
        pasteboard.setString(body, forType: .string)
    }

    static func copyRichText(_ source: Source) async {
        let html = await standaloneHTML(source, forRichText: true)
        guard let attributed = try? NSAttributedString(
            data: Data(html.utf8),
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil)
        else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let rtf = try? attributed.data(from: NSRange(location: 0, length: attributed.length),
                                          documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            pasteboard.setData(rtf, forType: .rtf)
        }
        pasteboard.setString(html, forType: .html)
        pasteboard.setString(attributed.string, forType: .string)
    }

    // MARK: - HTML

    static func renderedBody(_ source: Source) async -> String {
        let renderer = await OffscreenRenderer.render(source)
        defer { renderer.close() }
        return await renderer.preview.exportedBodyHTML()
    }

    /// A self-contained HTML document with the theme's CSS inlined.
    static func standaloneHTML(_ source: Source, forRichText: Bool = false) async -> String {
        let body = await renderedBody(source)
        let web = PreviewSchemeHandler.webRoot
        func css(_ path: String) -> String {
            (try? String(contentsOf: web.appending(path: path), encoding: .utf8)) ?? ""
        }
        var styles = css("themes/base.css") + "\n" + css("themes/\(source.configuration.theme.rawValue).css")
        if !source.configuration.customCSS.isEmpty { styles += "\n" + source.configuration.customCSS }

        var head = """
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(source.title))</title>
        <style>
        \(styles)
        </style>
        """
        if forRichText {
            head += "\n<style>\(css("vendor/highlight/github.min.css"))</style>"
        } else {
            head += """

            <style media="(prefers-color-scheme: light), print">\(css("vendor/highlight/github.min.css"))</style>
            <style media="screen and (prefers-color-scheme: dark)">\(css("vendor/highlight/github-dark.min.css"))</style>
            """
            if body.contains("class=\"katex") {
                // KaTeX fonts are loaded from the CDN so the file stays small.
                let katex = css("vendor/katex/katex.min.css")
                    .replacingOccurrences(of: "url(fonts/", with: "url(https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/")
                head += "\n<style>\(katex)</style>"
            }
        }
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        \(head)
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        </body>
        </html>
        """
    }

    private static func escape(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    }

    // MARK: - Helpers

    private static func printInfo() -> NSPrintInfo {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.topMargin = 54
        info.bottomMargin = 54
        info.leftMargin = 54
        info.rightMargin = 54
        return info
    }

    private static func savePanel(for source: Source, type: UTType, extension ext: String) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(source.title).\(ext)"
        if let directory = source.documentURL?.deletingLastPathComponent() {
            panel.directoryURL = directory
        }
        let response: NSApplication.ModalResponse
        if let window = source.window {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }
        return response == .OK ? panel.url : nil
    }

    private static func present(_ error: Error, in window: NSWindow?) {
        let alert = NSAlert(error: error)
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}

/// A preview web view in an invisible window, used for export and printing.
final class OffscreenRenderer {
    let preview = PreviewController()
    private let window: NSWindow
    private static var printDelegates: Set<PrintDelegate> = []

    private init(documentURL: URL?) {
        window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 900, height: 1200),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.contentView = preview.webView
        preview.documentDirectory = documentURL?.deletingLastPathComponent()
        window.orderFrontRegardless()
    }

    static func render(_ source: ExportService.Source) async -> OffscreenRenderer {
        let renderer = OffscreenRenderer(documentURL: source.documentURL)
        renderer.preview.configure(source.configuration)
        await renderer.preview.renderAndWait(source.markdown)
        return renderer
    }

    func print(info: NSPrintInfo, showPanels: Bool, title: String, hostWindow: NSWindow?) async {
        let operation = preview.webView.printOperation(with: info)
        operation.showsPrintPanel = showPanels
        operation.showsProgressPanel = showPanels
        operation.jobTitle = title
        operation.view?.frame = preview.webView.bounds
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let delegate = PrintDelegate { delegate in
                Self.printDelegates.remove(delegate)
                continuation.resume()
            }
            Self.printDelegates.insert(delegate)
            operation.runModal(for: hostWindow ?? window, delegate: delegate,
                               didRun: #selector(PrintDelegate.printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
    }

    func close() {
        window.contentView = nil
        window.close()
    }
}

/// NSPrintOperation reports completion on its own thread; hop back to main.
private final class PrintDelegate: NSObject, @unchecked Sendable {
    let completion: (PrintDelegate) -> Void

    init(completion: @escaping (PrintDelegate) -> Void) {
        self.completion = completion
    }

    @objc nonisolated func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.completion(self) }
        }
    }
}
