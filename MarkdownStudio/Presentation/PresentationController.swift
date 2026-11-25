#if os(macOS)
import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// A borderless window that can take keyboard focus.
private final class SlideWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// Runs a presentation: slides full screen, plus a presenter window with
/// notes and a timer on the other display when there are two.
final class PresentationController {
    static private(set) var current: PresentationController?

    private let slides: SlidesWebView
    private let state = PresentationState()
    private var slideWindow: SlideWindow?
    private var presenterWindow: NSWindow?
    private var previousOptions: NSApplication.PresentationOptions = []
    /// Names the slide and presenter windows for VoiceOver and the Window menu.
    private var documentName = "Untitled"

    private init(documentDirectory: URL?) {
        slides = SlidesWebView(documentDirectory: documentDirectory)
    }

    static func start(markdown: String, documentURL: URL?, configuration: PreviewConfiguration,
                      separator: SlideSeparator, from window: NSWindow?) {
        current?.stop()
        let controller = PresentationController(documentDirectory: documentURL?.deletingLastPathComponent())
        current = controller
        controller.documentName = documentURL?.deletingPathExtension().lastPathComponent ?? window?.title ?? "Untitled"
        controller.present(markdown: markdown, configuration: configuration, separator: separator, from: window)
    }

    private func present(markdown: String, configuration: PreviewConfiguration, separator: SlideSeparator, from window: NSWindow?) {
        let screens = NSScreen.screens
        let presenterScreen = window?.screen ?? NSScreen.main ?? screens.first
        let slideScreen = screens.count > 1 ? (screens.first { $0 != presenterScreen } ?? presenterScreen) : presenterScreen
        guard let slideScreen else { return }

        let slideWindow = SlideWindow(contentRect: slideScreen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        slideWindow.isReleasedWhenClosed = false
        slideWindow.backgroundColor = .black
        slideWindow.level = .normal
        slideWindow.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        slideWindow.contentView = slides.webView
        slideWindow.setFrame(slideScreen.frame, display: true)
        slideWindow.onEscape = { [weak self] in self?.stop() }
        slideWindow.title = "\(documentName), presentation"
        self.slideWindow = slideWindow

        previousOptions = NSApp.presentationOptions
        if slideScreen == NSScreen.screens.first {
            NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
        }
        slideWindow.makeKeyAndOrderFront(nil)
        slideWindow.makeFirstResponder(slides.webView)

        if screens.count > 1, let presenterScreen, presenterScreen != slideScreen {
            showPresenter(on: presenterScreen)
        }

        slides.onSlide = { [weak self] body in
            guard let self else { return }
            state.index = body["index"] as? Int ?? 0
            state.count = body["count"] as? Int ?? 0
            state.notes = body["notes"] as? String ?? ""
            state.title = body["title"] as? String ?? ""
            state.nextTitle = body["nextTitle"] as? String ?? ""
        }
        slides.onExit = { [weak self] in self?.stop() }

        let options = SlidesWebView.options(configuration, separator: separator, title: documentName)
        Task {
            let count = await slides.load(markdown, options: options)
            state.startedAt = Date()
            if count == 0 {
                let alert = NSAlert()
                alert.messageText = "Nothing to present"
                alert.informativeText = "Add some content to the document first."
                alert.runModal()
                stop()
            }
        }
    }

    private func showPresenter(on screen: NSScreen) {
        let view = PresenterView(state: state,
                                 previous: { [weak self] in self?.slides.run("MDSlides.previous()") },
                                 next: { [weak self] in self?.slides.run("MDSlides.next()") },
                                 end: { [weak self] in self?.stop() })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "\(documentName), presenter"
        window.contentView = NSHostingView(rootView: view)
        let frame = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: frame.midX - 380, y: frame.midY - 260))
        window.orderFront(nil)
        presenterWindow = window
    }

    func stop() {
        NSApp.presentationOptions = previousOptions
        slideWindow?.orderOut(nil)
        slideWindow?.contentView = nil
        presenterWindow?.orderOut(nil)
        slideWindow = nil
        presenterWindow = nil
        if Self.current === self { Self.current = nil }
    }

    // MARK: - Export

    /// Renders the slides offscreen and saves them as a 16:9 landscape PDF.
    static func exportPDF(markdown: String, title: String, documentURL: URL?, configuration: PreviewConfiguration,
                          separator: SlideSeparator, window: NSWindow?) async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(title) Slides.pdf"
        if let directory = documentURL?.deletingLastPathComponent() { panel.directoryURL = directory }
        let response = window != nil ? await panel.beginSheetModal(for: window!) : panel.runModal()
        guard response == .OK, let url = panel.url else { return }
        await renderPDF(markdown: markdown, to: url, documentURL: documentURL, configuration: configuration,
                        separator: separator, hostWindow: window)
    }

    /// Also used by tests. Returns the number of slides.
    @discardableResult
    static func renderPDF(markdown: String, to url: URL, documentURL: URL?, configuration: PreviewConfiguration,
                          separator: SlideSeparator, hostWindow: NSWindow?) async -> Int {
        let slides = SlidesWebView(documentDirectory: documentURL?.deletingLastPathComponent())
        let window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 1280, height: 720),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.alphaValue = 0
        window.contentView = slides.webView
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }

        let title = documentURL?.deletingPathExtension().lastPathComponent ?? url.deletingPathExtension().lastPathComponent
        let count = await slides.load(markdown, options: SlidesWebView.options(configuration, separator: separator, title: title))

        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        // Slides are 1280×720 CSS pixels; WebKit prints 96 px per inch and PDF uses 72 pt per inch.
        info.paperSize = NSSize(width: 960, height: 540)
        info.orientation = .landscape
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        await OffscreenRenderer.runPrint(webView: slides.webView, info: info, showPanels: false,
                                         title: url.deletingPathExtension().lastPathComponent, hostWindow: hostWindow ?? window)
        return count
    }
}

private struct PresenterView: View {
    let state: PresentationState
    let previous: () -> Void
    let next: () -> Void
    let end: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.count == 0 ? "Loading…" : "Slide \(state.index + 1) of \(state.count)")
                    .font(.title2.bold())
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = Int(context.date.timeIntervalSince(state.startedAt))
                    Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                }
            }
            if !state.title.isEmpty {
                Text(state.title).font(.title3)
            }
            GroupBox("Notes") {
                ScrollView {
                    Text(state.notes.isEmpty ? "No notes. Add <!-- notes: … --> to the slide." : state.notes)
                        .font(.title3)
                        .foregroundStyle(state.notes.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            HStack {
                Text(state.nextTitle.isEmpty ? (state.index + 1 >= state.count ? "Last slide" : "Next slide")
                     : "Next: \(state.nextTitle)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: previous) { Label("Previous", systemImage: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button(action: next) { Label("Next", systemImage: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .buttonStyle(.borderedProminent)
                Button("End", role: .destructive, action: end)
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 380)
    }
}
#endif
