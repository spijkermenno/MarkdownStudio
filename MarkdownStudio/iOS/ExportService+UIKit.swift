#if os(iOS)
import UIKit
import UniformTypeIdentifiers
import WebKit

/// Export on iPhone and iPad: files are written to a temporary folder and
/// handed to the share sheet (which offers Save to Files, AirDrop, Mail, …).
extension ExportService {
    static func htmlFile(_ source: Source) async throws -> URL {
        let url = try exportURL(named: source.title, extension: "html")
        try Data(await standaloneHTML(source).utf8).write(to: url)
        return url
    }

    static func pdfFile(_ source: Source) async throws -> URL {
        let url = try exportURL(named: source.title, extension: "pdf")
        let renderer = await OffscreenRenderer.render(source)
        defer { renderer.close() }
        try PDFRenderer.pdf(from: renderer.preview.webView, paperSize: PDFRenderer.defaultPaperSize, margin: 54).write(to: url)
        return url
    }

    static func print(_ source: Source) async {
        let renderer = await OffscreenRenderer.render(source)
        defer { renderer.close() }
        let info = UIPrintInfo.printInfo()
        info.jobName = source.title
        info.outputType = .general
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printFormatter = renderer.preview.webView.viewPrintFormatter()
        // The renderer has to stay alive until printing is done or cancelled.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            controller.present(animated: true) { _, _, _ in continuation.resume() }
        }
    }

    static func copyHTML(_ source: Source) async {
        let body = await renderedBody(source)
        UIPasteboard.general.setItems([[UTType.html.identifier: body, UTType.utf8PlainText.identifier: body]])
    }

    static func copyRichText(_ source: Source) async {
        let html = await standaloneHTML(source, forRichText: true)
        guard let attributed = try? NSAttributedString(
            data: Data(html.utf8),
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil)
        else { return }
        var item: [String: Any] = [UTType.html.identifier: html, UTType.utf8PlainText.identifier: attributed.string]
        if let rtf = try? attributed.data(from: NSRange(location: 0, length: attributed.length),
                                          documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            item[UTType.rtf.identifier] = rtf
        }
        UIPasteboard.general.setItems([item])
    }

    /// A fresh temporary folder per export, so the file keeps the document's name.
    static func exportURL(named name: String, extension ext: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Export", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return folder.appendingPathComponent(safeName.isEmpty ? "Untitled" : safeName).appendingPathExtension(ext)
    }
}

/// A preview web view parked just outside the visible area of the front
/// window: WebKit only lays out and animates views that are in a window,
/// and export waits for diagrams and math to finish.
final class OffscreenRenderer {
    let preview = PreviewController()

    private init(documentURL: URL?) {
        Self.park(preview.webView, size: CGSize(width: 900, height: 1200))
        preview.documentDirectory = documentURL?.deletingLastPathComponent()
    }

    static func render(_ source: ExportService.Source) async -> OffscreenRenderer {
        let renderer = OffscreenRenderer(documentURL: source.documentURL)
        renderer.preview.documentTitle = source.title
        renderer.preview.configure(source.configuration)
        await renderer.preview.renderAndWait(source.markdown)
        return renderer
    }

    /// Light appearance, out of sight and out of reach of touches and VoiceOver.
    static func park(_ webView: WKWebView, size: CGSize) {
        webView.frame = CGRect(origin: CGPoint(x: -size.width - 10_000, y: 0), size: size)
        webView.overrideUserInterfaceStyle = .light
        webView.isUserInteractionEnabled = false
        webView.accessibilityElementsHidden = true
        Platform.keyWindow?.addSubview(webView)
    }

    func close() {
        preview.webView.removeFromSuperview()
    }
}

/// Paginates a web view into a PDF.
enum PDFRenderer {
    /// A4, or US Letter where that's the usual paper size.
    static var defaultPaperSize: CGSize {
        Locale.current.measurementSystem == .us ? CGSize(width: 612, height: 792) : CGSize(width: 595.2, height: 841.8)
    }

    static func pdf(from webView: WKWebView, paperSize: CGSize, margin: CGFloat) -> Data {
        let renderer = PageRenderer(paper: CGRect(origin: .zero, size: paperSize), margin: margin)
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, renderer.paperRect, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        let bounds = UIGraphicsGetPDFContextBounds()
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: bounds)
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    nonisolated private final class PageRenderer: UIPrintPageRenderer {
        private let paper: CGRect
        private let margin: CGFloat

        init(paper: CGRect, margin: CGFloat) {
            self.paper = paper
            self.margin = margin
        }

        override var paperRect: CGRect { paper }
        override var printableRect: CGRect { paper.insetBy(dx: margin, dy: margin) }
    }
}
#endif
