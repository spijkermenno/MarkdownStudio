import SwiftUI

struct DocumentView: View {
    let document: MarkdownDocument
    let fileURL: URL?

    @State private var session: DocumentSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(macOS)
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    #else
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.undoManager) private var undoManager
    @State private var isShowingOutline = false
    @State private var isShowingSettings = false
    @State private var isShowingCheatSheet = false
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceMode.system
    #endif

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
        layout
            .toolbar { toolbar }
            .focusedSceneValue(\.session, session)
            .sheet(isPresented: $session.isShowingGoToLine) {
                GoToLineView(session: session)
                    #if os(iOS)
                    .presentationDetents([.height(190)])
                    #endif
            }
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
            .onChange(of: session.viewMode) { _, mode in storedViewMode = mode.rawValue }
            .onChange(of: session.splitOrientation) { _, orientation in storedOrientation = orientation.rawValue }
    }

    #if os(macOS)
    private var layout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(session: session)
                .tourHighlight(session.tourTarget == .sidebar)
                .navigationSplitViewColumnWidth(min: 190, ideal: 240, max: 400)
        } detail: {
            detail
        }
        .frame(minWidth: 560, minHeight: 360)
        .toolbar(session.distractionFree ? .hidden : .automatic, for: .windowToolbar)
        .background(WindowAccessor { session.window = $0 })
        .onChange(of: session.sidebarRequest) { _, _ in columnVisibility = .all }
        .onChange(of: session.isInWorkspace) { _, inside in showFolderTree(inside) }
        .onChange(of: columnVisibility) { _, visibility in showOutline = visibility != .detailOnly }
        .onChange(of: session.distractionFree) { _, enabled in
            columnVisibility = enabled || !showOutline ? .detailOnly : .all
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if showFormattingBar && session.viewMode.showsEditor && !session.distractionFree {
                FormattingBar(session: session)
                Divider()
            }
            documentArea
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
    #else
    private var isCompact: Bool { horizontalSizeClass == .compact }

    /// iPhones (and narrow iPad windows) show the editor or the preview, not both.
    private var displayedViewMode: ViewMode {
        isCompact && session.viewMode == .split ? .editor : session.viewMode
    }

    /// The bars under the document give way to the keyboard on small screens.
    private var showsBottomBars: Bool { !(isCompact && session.isEditing) }

    private var layout: some View {
        detail
            .toolbarRole(.editor)
            .inspector(isPresented: $isShowingOutline) {
                OutlineView(session: session, onJump: {
                    // On iPhone the outline covers the document, so get out of the way.
                    if isCompact { isShowingOutline = false }
                })
                .inspectorColumnWidth(min: 220, ideal: 280, max: 400)
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $isShowingSettings) { SettingsView() }
            .sheet(isPresented: $isShowingCheatSheet) {
                NavigationStack {
                    CheatSheetView()
                        .navigationTitle("Cheat Sheet")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isShowingCheatSheet = false }
                            }
                        }
                }
            }
            .sheet(item: $session.sharedFile) { file in
                ShareSheet(url: file.url)
                    .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $session.isPresentingSlides) {
                SlideShowView(markdown: session.text, title: session.title, documentDirectory: session.slidesDirectory,
                              configuration: previewConfiguration, separator: slideSeparator) { message in
                    session.isPresentingSlides = false
                    if let message { session.showToast(message, systemImage: "rectangle.on.rectangle.slash") }
                }
            }
            .overlay {
                if session.isExporting {
                    ProgressView("Preparing…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .onChange(of: session.sidebarRequest) { _, _ in isShowingOutline = true }
            .onChange(of: showFormattingBar, initial: true) { _, show in session.editor.showsFormattingBar = show }
            .onChange(of: undoManager.map(ObjectIdentifier.init), initial: true) { _, _ in
                session.editor.textView.documentUndoManager = undoManager
            }
            .onChange(of: appearance) { _, mode in Platform.apply(mode) }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            documentArea
            if showProblems && checkDocument && showsBottomBars {
                Divider()
                ProblemsPanel(session: session)
            }
            if showStatusBar && showsBottomBars {
                Divider()
                StatusBarView(session: session)
            }
        }
    }
    #endif

    /// The editor and/or preview, with the toast and the tour card on top.
    private var documentArea: some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = session.toast {
                    ToastView(toast: toast, hovering: { session.isToastHovered = $0 }) { session.toast = nil }
                        .padding(.bottom, 14)
                        .padding(.horizontal, 16)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: session.toast?.id)
            .overlay(alignment: tourCardAlignment) {
                TourCard(session: session).padding(20)
            }
            .animation(.easeOut(duration: 0.25), value: session.tourStep)
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
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
        #else
        switch displayedViewMode {
        case .editor:
            editorPane
        case .preview:
            previewPane
        case .split:
            let horizontal = session.splitOrientation == .horizontal
            SplitPane(axis: horizontal ? .horizontal : .vertical, minimum: horizontal ? 220 : 120) {
                editorPane
            } second: {
                previewPane
            }
        }
        #endif
    }

    private var editorPane: some View {
        EditorHost(controller: session.editor)
            .tourHighlight(session.tourTarget == .editor)
            #if os(iOS)
            .overlay {
                if session.isEmpty && !session.isEditing {
                    TemplatePicker(session: session)
                        .padding(20)
                        .transition(.opacity)
                }
            }
            #endif
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

    #if os(macOS)
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
    #else
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View Mode", selection: Binding(get: { displayedViewMode }, set: { session.viewMode = $0 })) {
                ForEach(isCompact ? [ViewMode.editor, .preview] : ViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .labelStyle(.iconOnly)
                        .accessibilityLabel(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if !isCompact {
                if session.viewMode == .split {
                    Button {
                        session.splitOrientation = session.splitOrientation == .horizontal ? .vertical : .horizontal
                    } label: {
                        Label(session.splitOrientation == .horizontal ? "Split Top and Bottom" : "Split Side by Side",
                              systemImage: session.splitOrientation == .horizontal ? "rectangle.split.1x2" : "rectangle.split.2x1")
                    }
                }
                Button {
                    session.startPresentation(separator: slideSeparator)
                } label: {
                    Label("Present", systemImage: "play.rectangle")
                }
                Menu {
                    exportItems
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                isShowingOutline.toggle()
            } label: {
                Label("Outline", systemImage: "list.bullet.indent")
            }
            Menu {
                if isCompact {
                    Button("Present", systemImage: "play.rectangle") { session.startPresentation(separator: slideSeparator) }
                    Menu("Export", systemImage: "square.and.arrow.up") { exportItems }
                    Divider()
                }
                Button("Go to Line…", systemImage: "arrow.right.to.line") { session.isShowingGoToLine = true }
                if checkDocument {
                    Toggle(isOn: $showProblems) { Label("Show Problems", systemImage: "exclamationmark.triangle") }
                }
                Divider()
                Button("Markdown Cheat Sheet", systemImage: "questionmark.circle") { isShowingCheatSheet = true }
                Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }

    @ViewBuilder
    private var exportItems: some View {
        Button("Share as HTML…", systemImage: "chevron.left.forwardslash.chevron.right", action: session.exportHTML)
        Button("Share as PDF…", systemImage: "doc.richtext", action: session.exportPDF)
        Button("Share Slides as PDF…", systemImage: "rectangle.on.rectangle") { session.exportSlidesPDF(separator: slideSeparator) }
        Divider()
        Button("Copy as HTML", systemImage: "doc.on.clipboard", action: session.copyHTML)
        Button("Copy as Rich Text", systemImage: "doc.on.clipboard.fill", action: session.copyRichText)
        Divider()
        Button("Print…", systemImage: "printer", action: session.printDocument)
    }
    #endif

    #if os(macOS)
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

    #endif

    private func setUp() {
        #if os(macOS)
        // A document is open, so the Welcome window has done its job.
        WelcomeWindow.openWindow = openWindow
        dismissWindow(id: WelcomeWindow.id)
        #endif
        if let mode = ViewMode(rawValue: storedViewMode) { session.viewMode = mode }
        if let orientation = SplitOrientation(rawValue: storedOrientation) { session.splitOrientation = orientation }
        #if os(macOS)
        columnVisibility = showOutline ? .all : .detailOnly
        #else
        Platform.apply(appearance)
        #endif
        session.onTextChange = { [document] in document.text = $0 }
        session.syncScroll = syncScroll
        session.checkDocument = checkDocument
        session.applyPreviewConfiguration(previewConfiguration)
        session.editor.configure(editorConfiguration)
        session.start()
        #if os(macOS)
        showFolderTree(session.isInWorkspace)
        if document.isTour {
            session.startTour()
        } else if Onboarding.shouldPresentAutomatically() {
            openWindow(id: Onboarding.windowID)
        }
        #endif
    }
}

#if os(iOS)
/// Shown in an empty document: start from one of the templates (File → New
/// from Template on the Mac) or just start typing.
private struct TemplatePicker: View {
    let session: DocumentSession
    @State private var templates: [DocumentTemplate] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Start from a template")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            ForEach(templates) { template in
                row(template.name, systemImage: "doc.text") { session.insertTemplate(template.filled()) }
            }
            row("Markdown Showcase", systemImage: "sparkles") { session.insertTemplate(Showcase.text) }
            Text("Or tap anywhere to start typing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 6)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.separator))
        .onAppear { templates = TemplateLibrary.all }
    }

    private func row(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif

#if os(macOS)
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
#endif
