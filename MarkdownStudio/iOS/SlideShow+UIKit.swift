#if os(iOS)
import SwiftUI
import UIKit
import WebKit

/// Plays a document's slides full screen. Tap the right of a slide or swipe
/// left for the next one; tap the left quarter or swipe right to go back.
/// A hardware keyboard's arrow keys and Escape work too.
struct SlideShowView: View {
    let markdown: String
    let title: String
    let documentDirectory: URL?
    let configuration: PreviewConfiguration
    let separator: SlideSeparator
    /// Called when the show ends; the message explains why it ended early.
    let onEnd: (_ message: String?) -> Void

    @State private var slides: SlidesWebView?
    @State private var state = PresentationState()
    @State private var showsNotes = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let slides {
                SlidesHost(slides: slides)
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .topLeading) { controls }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .background {
            // Keyboard navigation for iPads with a keyboard.
            Group {
                Button("Next Slide") { slides?.run("MDSlides.next()") }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("Next Slide") { slides?.run("MDSlides.next()") }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Previous Slide") { slides?.run("MDSlides.previous()") }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("End Presentation") { onEnd(nil) }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .task { await start() }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                onEnd(nil)
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("End Presentation")
            Button {
                showsNotes.toggle()
                slides?.run("MDSlides.showNotes(\(showsNotes))")
            } label: {
                Image(systemName: showsNotes ? "note.text" : "note.text.badge.plus")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(showsNotes ? "Hide Notes" : "Show Notes")
            if state.count > 0 {
                Text("\(state.index + 1) / \(state.count)")
                    .font(.callout.monospacedDigit())
                    .padding(.trailing, 12)
                    .accessibilityLabel("Slide \(state.index + 1) of \(state.count)")
            }
        }
        .foregroundStyle(.white)
        .background(.black.opacity(0.35), in: Capsule())
        .padding(12)
    }

    private func start() async {
        let slides = SlidesWebView(documentDirectory: documentDirectory)
        slides.onSlide = { body in
            state.index = body["index"] as? Int ?? 0
            state.count = body["count"] as? Int ?? 0
            state.notes = body["notes"] as? String ?? ""
            state.title = body["title"] as? String ?? ""
            state.nextTitle = body["nextTitle"] as? String ?? ""
        }
        slides.onExit = { onEnd(nil) }
        self.slides = slides
        let count = await slides.load(markdown, options: SlidesWebView.options(configuration, separator: separator, title: title))
        state.startedAt = Date()
        if count == 0 { onEnd("Nothing to present. Add some content to the document first.") }
    }

    /// Renders the slides offscreen and saves them as a 16:9 landscape PDF.
    static func pdfFile(markdown: String, title: String, documentURL: URL?, configuration: PreviewConfiguration,
                        separator: SlideSeparator) async throws -> URL {
        let url = try ExportService.exportURL(named: "\(title) Slides", extension: "pdf")
        let slides = SlidesWebView(documentDirectory: documentURL?.deletingLastPathComponent())
        OffscreenRenderer.park(slides.webView, size: CGSize(width: 1280, height: 720))
        defer { slides.webView.removeFromSuperview() }
        _ = await slides.load(markdown, options: SlidesWebView.options(configuration, separator: separator, title: title))
        // Slides are 1280×720 CSS pixels; WebKit prints 96 px per inch and PDF uses 72 pt per inch.
        try PDFRenderer.pdf(from: slides.webView, paperSize: CGSize(width: 960, height: 540), margin: 0).write(to: url)
        return url
    }
}

private struct SlidesHost: UIViewRepresentable {
    let slides: SlidesWebView

    func makeUIView(context: Context) -> WKWebView {
        let webView = slides.webView
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swiped(_:)))
            swipe.direction = direction
            webView.addGestureRecognizer(swipe)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(slides: slides) }

    final class Coordinator: NSObject {
        let slides: SlidesWebView
        init(slides: SlidesWebView) { self.slides = slides }

        @objc func swiped(_ recognizer: UISwipeGestureRecognizer) {
            slides.run(recognizer.direction == .left ? "MDSlides.next()" : "MDSlides.previous()")
        }
    }
}
#endif
