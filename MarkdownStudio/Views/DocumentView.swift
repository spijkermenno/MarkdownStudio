import SwiftUI

struct DocumentView: View {
    let document: MarkdownDocument
    let fileURL: URL?

    @State private var session: DocumentSession
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    @SceneStorage("viewMode") private var storedViewMode = ""
    @SceneStorage("splitOrientation") private var storedOrientation = ""
    @SceneStorage("showOutline") private var showOutline = false

    @AppStorage(SettingsKey.editorFontName) private var fontName = ""
    @AppStorage(SettingsKey.editorFontSize) private var fontSize = 14.0
    @AppStorage(SettingsKey.showLineNumbers) private var showLineNumbers = false
    @AppStorage(SettingsKey.highlightCurrentLine) private var highlightCurrentLine = true
    @AppStorage(SettingsKey.typewriterScrolling) private var typewriterScrolling = false
    @AppStorage(SettingsKey.focusMode) private var focusMode = false
    @AppStorage(SettingsKey.autoPairing) private var autoPairing = true
    @AppStorage(SettingsKey.smartLists) private var smartLists = true
    @AppStorage(SettingsKey.spellCheck) private var spellCheck = true
    @AppStorage(SettingsKey.syntaxHighlighting) private var syntaxHighlighting = true
    @AppStorage(SettingsKey.previewTheme) private var previewTheme = PreviewTheme.github
    @AppStorage(SettingsKey.customCSS) private var customCSS = ""
    @AppStorage(SettingsKey.renderMath) private var renderMath = true
    @AppStorage(SettingsKey.renderMermaid) private var renderMermaid = true
    @AppStorage(SettingsKey.frontMatterStyle) private var frontMatterStyle = FrontMatterStyle.table
    @AppStorage(SettingsKey.syncScroll) private var syncScroll = true
    @AppStorage(SettingsKey.showStatusBar) private var showStatusBar = true
    @AppStorage(SettingsKey.showFormattingBar) private var showFormattingBar = false
    @AppStorage(SettingsKey.autocomplete) private var autocomplete = true
    @AppStorage(SettingsKey.pasteAsMarkdown) private var pasteAsMarkdown = true
    @AppStorage(SettingsKey.checkDocument) private var checkDocument = true
    @AppStorage(SettingsKey.showProblems) private var showProblems = false
    @AppStorage(SettingsKey.slideSeparator) private var slideSeparator = SlideSeparator.automatic

    init(document: MarkdownDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        let defaults = UserDefaults.standard
        let mode = ViewMode(rawValue: defaults.string(forKey: SettingsKey.defaultViewMode) ?? "") ?? .split
        let orientation = SplitOrientation(rawValue: defaults.string(forKey: SettingsKey.defaultSplitOrientation) ?? "") ?? .horizontal
        _session = State(initialValue: DocumentSession(text: document.text, fileURL: fileURL,
                                                       viewMode: mode, splitOrientation: orientation))
    }

    private var editorConfiguration: EditorConfiguration {
        EditorConfiguration(fontName: fontName, fontSize: fontSize, zoom: session.zoom,
                            showLineNumbers: showLineNumbers, highlightCurrentLine: highlightCurrentLine,
                            typewriterScrolling: typewriterScrolling, focusMode: focusMode,
                            autoPairing: autoPairing, smartLists: smartLists, spellCheck: spellCheck,
                            syntaxHighlighting: syntaxHighlighting, autocomplete: autocomplete,
                            pasteAsMarkdown: pasteAsMarkdown)
    }

    private var previewConfiguration: PreviewConfiguration {
        PreviewConfiguration(theme: previewTheme, customCSS: customCSS, math: renderMath,
                             mermaid: renderMermaid, frontMatter: frontMatterStyle)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(session: session)
                .tourHighlight(session.tourTarget == .sidebar)
                .navigationSplitViewColumnWidth(min: 190, ideal: 240, max: 400)
        } detail: {
            VStack(spacing: 0) {
                if showFormattingBar && session.viewMode.showsEditor && !session.distractionFree {
                    FormattingBar(session: session)
                    Divider()
                }
                content
                    .overlay(alignment: .bottom) {
                        if let toast = session.toast {
                            ToastView(toast: toast, hovering: { session.isToastHovered = $0 }) { session.toast = nil }
                                .padding(.bottom, 14)
                                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: session.toast?.id)
                    .overlay(alignment: tourCardAlignment) {
                        TourCard(session: session).padding(20)
                    }
                    .animation(.easeOut(duration: 0.25), value: session.tourStep)
                if showProblems && checkDocument && !session.distractionFree {
                    Divider()
                    ProblemsPanel(session: session)
                }
                if showStatusBar && !session.distractionFree {
                    Divider()
                    StatusBarView(session: session)
                        .tourHighlight(session.tourTarget == .statusBar, inset: 0)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .toolbar { toolbar }
        .toolbar(session.distractionFree ? .hidden : .automatic, for: .windowToolbar)
        .focusedSceneValue(\.session, session)
        .background(WindowAccessor { session.window = $0 })
        .sheet(isPresented: $session.isShowingGoToLine) { GoToLineView(session: session) }
        .onAppear(perform: setUp)
        // A revert hands us a freshly read document object.
        .onChange(of: ObjectIdentifier(document)) { _, _ in
            session.onTextChange = { [document] in document.text = $0 }
            session.documentTextChanged(document.text)
        }
        .onChange(of: fileURL) { _, url in session.fileURL = url }
        .onChange(of: editorConfiguration) { _, configuration in session.editor.configure(configuration) }
        .onChange(of: previewConfiguration) { _, configuration in session.applyPreviewConfiguration(configuration) }
        .onChange(of: syncScroll) { _, value in session.syncScroll = value }
        .onChange(of: checkDocument) { _, value in session.checkDocument = value }
        .onChange(of: session.sidebarRequest) { _, _ in columnVisibility = .all }
        .onChange(of: session.isInWorkspace) { _, inside in showFolderTree(inside) }
        .onChange(of: session.viewMode) { _, mode in storedViewMode = mode.rawValue }
        .onChange(of: session.splitOrientation) { _, orientation in storedOrientation = orientation.rawValue }
        .onChange(of: columnVisibility) { _, visibility in showOutline = visibility != .detailOnly }
        .onChange(of: session.distractionFree) { _, enabled in
            columnVisibility = enabled || !showOutline ? .detailOnly : .all
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.viewMode {
        case .editor:
            editorPane
        case .preview:
            previewPane
        case .split:
            if session.splitOrientation == .horizontal {
                HSplitView {
                    editorPane.frame(minWidth: 220, maxWidth: .infinity)
                    previewPane.frame(minWidth: 220, maxWidth: .infinity)
                }
            } else {
                VSplitView {
                    editorPane.frame(minHeight: 120, maxHeight: .infinity)
                    previewPane.frame(minHeight: 120, maxHeight: .infinity)
                }
            }
        }
    }

    private var editorPane: some View {
        EditorHost(controller: session.editor).tourHighlight(session.tourTarget == .editor)
    }

    private var previewPane: some View {
        PreviewHost(controller: session.preview).tourHighlight(session.tourTarget == .preview)
    }

    /// Keeps the tour card away from the part it's describing.
    private var tourCardAlignment: Alignment {
        switch session.tourTarget {
        case .editor: .bottomTrailing
        case .preview, .sidebar: .bottomLeading
        case .statusBar, .shareButtons, .viewModes: .bottomTrailing
        case .none: .center
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View Mode", selection: $session.viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Editor ⌘1 · Split ⌘2 · Preview ⌘3")
            .tourHighlight(session.tourTarget == .viewModes, inset: -4)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                session.splitOrientation = session.splitOrientation == .horizontal ? .vertical : .horizontal
            } label: {
                Label("Split Orientation",
                      systemImage: session.splitOrientation == .horizontal ? "rectangle.split.1x2" : "rectangle.split.2x1")
            }
            .disabled(session.viewMode != .split)
            .help(session.splitOrientation == .horizontal ? "Split Top and Bottom" : "Split Side by Side")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                session.startPresentation(separator: slideSeparator)
            } label: {
                Label("Present", systemImage: "play.rectangle")
            }
            .help("Start Presentation (⌥⌘P)")
            .tourHighlight(session.tourTarget == .shareButtons, inset: -4)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Export as HTML…", action: session.exportHTML)
                Button("Export as PDF…", action: session.exportPDF)
                Button("Export Slides as PDF…") { session.exportSlidesPDF(separator: slideSeparator) }
                Divider()
                Button("Copy as HTML", action: session.copyHTML)
                Button("Copy as Rich Text", action: session.copyRichText)
                Divider()
                Button("Print…", action: session.printDocument)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .tourHighlight(session.tourTarget == .shareButtons, inset: -4)
            .help("Export, copy or print the rendered document")
        }
    }

    /// Documents from the open folder show its tree; others fall back to the outline.
    private func showFolderTree(_ inside: Bool) {
        session.updateTabBar()
        if inside {
            // Opened as a tab: keep the sidebar the previous tab was showing.
            session.sidebarTab = WorkspaceNavigator.takePendingSidebarTab(for: session.fileURL) ?? .files
            columnVisibility = .all
        } else if session.sidebarTab != .outline {
            session.sidebarTab = .outline
        }
    }

    private func setUp() {
        // A document is open, so the Welcome window has done its job.
        WelcomeWindow.openWindow = openWindow
        dismissWindow(id: WelcomeWindow.id)
        if let mode = ViewMode(rawValue: storedViewMode) { session.viewMode = mode }
        if let orientation = SplitOrientation(rawValue: storedOrientation) { session.splitOrientation = orientation }
        columnVisibility = showOutline ? .all : .detailOnly
        session.onTextChange = { [document] in document.text = $0 }
        session.syncScroll = syncScroll
        session.checkDocument = checkDocument
        session.applyPreviewConfiguration(previewConfiguration)
        session.editor.configure(editorConfiguration)
        session.start()
        showFolderTree(session.isInWorkspace)
        if document.isTour {
            session.startTour()
        } else if Onboarding.shouldPresentAutomatically() {
            openWindow(id: Onboarding.windowID)
        }
    }
}

// MARK: - AppKit hosts

/// Hosts a session-owned AppKit view. The same view is reused across
/// view-mode changes (so it keeps text, selection, undo and scroll state);
/// whichever container most recently entered a window claims it.
final class ReparentingContainer: NSView {
    let hosted: NSView
    var focusOnAttach: NSView?

    init(hosted: NSView) {
        self.hosted = hosted
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { attach() }
    }

    func attach() {
        guard hosted.superview !== self else { return }
        hosted.removeFromSuperview()
        hosted.frame = bounds
        hosted.autoresizingMask = [.width, .height]
        addSubview(hosted)
        if let focusOnAttach {
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else { return }
                if window.firstResponder === window || window.firstResponder == nil {
                    window.makeFirstResponder(focusOnAttach)
                }
            }
        }
    }
}

struct EditorHost: NSViewRepresentable {
    let controller: EditorController

    func makeNSView(context: Context) -> ReparentingContainer {
        let container = ReparentingContainer(hosted: controller.scrollView)
        container.focusOnAttach = controller.textView
        return container
    }

    func updateNSView(_ container: ReparentingContainer, context: Context) {
        if container.window != nil { container.attach() }
    }
}

struct PreviewHost: NSViewRepresentable {
    let controller: PreviewController

    func makeNSView(context: Context) -> ReparentingContainer {
        ReparentingContainer(hosted: controller.webView)
    }

    func updateNSView(_ container: ReparentingContainer, context: Context) {
        if container.window != nil { container.attach() }
    }
}

/// Reports the hosting NSWindow.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let window = view.window { onWindow(window) }
    }
}
