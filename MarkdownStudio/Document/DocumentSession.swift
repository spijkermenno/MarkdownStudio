import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Per-window state: the editor and preview controllers, view mode, outline,
/// statistics and the glue between them (scroll sync, task toggles, …).
@Observable
final class DocumentSession {
    var viewMode: ViewMode
    var splitOrientation: SplitOrientation
    var zoom: Double = 1 {
        didSet { preview.zoom = zoom }
    }
    var syncScroll = true
    var distractionFree = false
    var isShowingGoToLine = false
    var toast: Toast?
    var sidebarTab: SidebarTab = .outline
    /// An untitled document created for the open folder (e.g. an empty folder).
    var createdInWorkspace = false
    /// The folder tree appears only for documents inside the open folder.
    var isInWorkspace: Bool {
        let workspace = Workspace.shared
        return workspace.rootURL != nil && ((fileURL == nil && createdInWorkspace) || workspace.contains(fileURL))
    }
    /// Incremented to ask the window to show the sidebar / focus folder search.
    var sidebarRequest = 0
    var searchFocusRequest = 0
    private(set) var problems: [DocumentProblem] = []
    /// The current step of the onboarding tour, if this window is running it.
    private(set) var tourStep: Int?
    var tourTarget: TourTarget { tourStep.map { TourStep.all[$0].target } ?? .none }
    @ObservationIgnored var checkDocument = true {
        didSet { if !checkDocument { problems = []; editor.showProblems([]) } else { scheduleAnalysis(editor.text, delay: 0) } }
    }

    /// The word goal for this document (front matter `goal:` or a per-file setting).
    private(set) var goal: Int?
    private(set) var wordsToday = 0
    @ObservationIgnored private var sessionGoal: Int?
    @ObservationIgnored private let untitledKey = "untitled-" + UUID().uuidString
    @ObservationIgnored private var hasAnalyzed = false

    private(set) var outline: [OutlineItem] = []
    private(set) var statistics = DocumentStatistics()
    private(set) var cursorLine = 0
    private(set) var cursorColumn = 0
    private(set) var selectionLength = 0

    var fileURL: URL? {
        didSet { updateFileURL() }
    }

    @ObservationIgnored weak var window: NSWindow?
    /// Writes edits back into the SwiftUI document.
    @ObservationIgnored var onTextChange: ((String) -> Void)?
    @ObservationIgnored var previewConfiguration = PreviewConfiguration()

    @ObservationIgnored private let initialText: String
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var fileWatcher: FileWatcher?

    // The AppKit views are created lazily: SwiftUI may construct throwaway
    // sessions while initialising views, and those shouldn't spin up web views.
    @ObservationIgnored private(set) lazy var editor: EditorController = makeEditor()
    @ObservationIgnored private(set) lazy var preview: PreviewController = makePreview()

    init(text: String, fileURL: URL?, viewMode: ViewMode, splitOrientation: SplitOrientation) {
        initialText = text
        self.fileURL = fileURL
        self.viewMode = viewMode
        self.splitOrientation = splitOrientation
    }

    /// Called once the window appears; computes the outline and statistics.
    func start() {
        if fileURL == nil, WorkspaceNavigator.nextUntitledBelongsToWorkspace {
            WorkspaceNavigator.nextUntitledBelongsToWorkspace = false
            createdInWorkspace = true
        }
        scheduleAnalysis(editor.text, delay: 0)
        watchFile()
        WorkspaceNavigator.register(self, for: fileURL)
    }

    private func makeEditor() -> EditorController {
        let editor = EditorController(text: initialText)
        editor.documentURL = fileURL
        editor.onTextChange = { [weak self] text in
            self?.textDidChange(text)
        }
        editor.onSelectionChange = { [weak self] line, column, length in
            self?.cursorLine = line
            self?.cursorColumn = column
            self?.selectionLength = length
        }
        editor.onScroll = { [weak self] line, atBottom in
            guard let self, syncScroll, viewMode == .split else { return }
            preview.scroll(toLine: line, atBottom: atBottom)
        }
        editor.htmlConverter = { [weak self] html in
            await self?.preview.markdown(fromHTML: html)
        }
        editor.textView.onPasteConverted = { [weak self, weak editor] in
            self?.showToast("Pasted as Markdown", systemImage: "doc.richtext", actionTitle: "Undo") {
                editor?.textView.undoManager?.undo()
            }
        }
        return editor
    }

    private func makePreview() -> PreviewController {
        let preview = PreviewController()
        preview.documentDirectory = fileURL?.deletingLastPathComponent()
        preview.zoom = zoom
        preview.configure(previewConfiguration)
        preview.render(editor.text)
        preview.onScroll = { [weak self] line, atBottom in
            guard let self, syncScroll, viewMode == .split else { return }
            editor.scroll(toLine: line, atBottom: atBottom)
        }
        preview.onReveal = { [weak self] line in
            guard let self else { return }
            if viewMode == .preview { viewMode = .split }
            editor.reveal(line: line)
        }
        preview.onToggleTask = { [weak self] line in
            self?.editor.toggleTask(atLine: line)
        }
        preview.onOpenDocument = { url in
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        }
        return preview
    }

    private func updateFileURL() {
        // A goal set before the first save now belongs to the file.
        if let url = fileURL, let goal = sessionGoal {
            WritingGoal.store(goal, for: url)
            sessionGoal = nil
        }
        editor.documentURL = fileURL
        preview.documentDirectory = fileURL?.deletingLastPathComponent()
        preview.render(editor.text)
        watchFile()
        WorkspaceNavigator.register(self, for: fileURL)
    }

    // MARK: - Changes made by other apps

    private func watchFile() {
        fileWatcher = fileURL.map { url in
            FileWatcher(url: url) { [weak self] in self?.fileDidChangeOnDisk() }
        }
    }

    /// Reloads the document when another app changed the file. If there are
    /// unsaved edits here as well, nothing is reloaded: the standard macOS
    /// "changed by another application" dialog appears on the next save.
    private func fileDidChangeOnDisk() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let diskText = try? MarkdownDocument.decode(data),
              diskText != editor.text,                       // ignores our own saves
              let document = NSDocumentController.shared.document(for: url),
              !document.isDocumentEdited
        else { return }
        do {
            // Reverting through NSDocument keeps its modification date in sync,
            // so the next autosave doesn't report a conflict.
            try document.revert(toContentsOf: url, ofType: document.fileType ?? UTType.markdownDocument.identifier)
        } catch {
            return
        }
        onTextChange?(diskText)
        documentTextChanged(diskText)
    }

    // MARK: - Text flow

    var text: String { editor.text }

    var title: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? window?.title ?? "Untitled"
    }

    private func textDidChange(_ text: String) {
        onTextChange?(text)
        scheduleRender(text)
        scheduleAnalysis(text)
    }

    /// Called when the document changed outside the editor (revert, versions).
    func documentTextChanged(_ text: String) {
        guard text != editor.text else { return }
        editor.setText(text)
        scheduleRender(text)
        scheduleAnalysis(text)
    }

    private func scheduleRender(_ text: String) {
        renderTask?.cancel()
        // Small documents render almost immediately; large ones wait for a pause in typing.
        let delay = (text as NSString).length > 50_000 ? 250 : 60
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            self?.preview.render(text)
        }
    }

    private func scheduleAnalysis(_ text: String, delay: Int = 300) {
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self else { return }
            let directory = self.fileURL?.deletingLastPathComponent()
            let check = self.checkDocument
            let (outline, statistics, problems) = await Task.detached(priority: .utility) {
                (OutlineParser.parse(text), DocumentStatistics(text),
                 check ? DocumentChecker.check(text, documentDirectory: directory) : [])
            }.value
            guard !Task.isCancelled else { return }
            let previousWords = self.statistics.words
            if self.outline != outline { self.outline = outline }
            if self.statistics != statistics { self.statistics = statistics }
            self.updateGoal(text: text, previousWords: previousWords)
            if self.problems != problems { self.problems = problems }
            // Only underline when the text hasn't moved on since the check started.
            if self.editor.text == text { self.editor.showProblems(problems) }
        }
    }

    // MARK: - Document check

    func select(_ problem: DocumentProblem) {
        if viewMode == .preview { viewMode = .split }
        editor.select(problem.range)
    }

    func fix(_ problem: DocumentProblem) {
        guard let fix = problem.fix else { return }
        if viewMode == .preview { viewMode = .split }
        editor.apply(fix.edit, actionName: fix.title)
    }

    // MARK: - Sidebar

    func showSidebar(_ tab: SidebarTab) {
        sidebarTab = tab
        sidebarRequest += 1
        if tab == .search { searchFocusRequest += 1 }
    }

    // MARK: - Tour

    func startTour() {
        TourStep.activeSession = self
        tourStep = 0
        TourStep.all[0].prepare(self)
    }

    func moveTour(by offset: Int) {
        guard let step = tourStep else { return }
        let next = max(0, min(step + offset, TourStep.all.count - 1))
        TourStep.all[next].prepare(self)
        tourStep = next
    }

    /// Finishing the last step completes onboarding; closing the tour early doesn't.
    func endTour(completed: Bool) {
        tourStep = nil
        if TourStep.activeSession === self { TourStep.activeSession = nil }
        if completed {
            Onboarding.markCompleted()
            showToast("Tour finished. Restart it any time in Settings → General.", systemImage: "checkmark.seal")
        }
    }

    // MARK: - Presentation

    func startPresentation(separator: SlideSeparator) {
        PresentationController.start(markdown: editor.text, documentURL: fileURL, configuration: previewConfiguration,
                                     separator: separator, from: window)
    }

    func exportSlidesPDF(separator: SlideSeparator) {
        Task {
            await PresentationController.exportPDF(markdown: editor.text, title: title, documentURL: fileURL,
                                                   configuration: previewConfiguration, separator: separator, window: window)
        }
    }

    // MARK: - Writing goal

    private func updateGoal(text: String, previousWords: Int) {
        let words = statistics.words
        let newGoal = WritingGoal.frontMatterGoal(in: text) ?? fileURL.flatMap(WritingGoal.storedGoal) ?? sessionGoal
        if hasAnalyzed, let newGoal, newGoal == goal, previousWords < newGoal, words >= newGoal {
            showToast("Goal reached: \(newGoal.formatted()) words", systemImage: "checkmark.circle.fill")
        }
        hasAnalyzed = true
        if goal != newGoal { goal = newGoal }
        let today = WritingGoal.wordsToday(current: words, for: fileURL?.standardizedFileURL.path ?? untitledKey)
        if wordsToday != today { wordsToday = today }
    }

    /// Whether the goal lives in the document's front matter.
    var goalIsInFrontMatter: Bool { WritingGoal.frontMatterGoal(in: editor.text) != nil }

    func setGoal(_ newGoal: Int?) {
        let text = editor.text
        if WritingGoal.frontMatterGoal(in: text) != nil, let edit = WritingGoal.frontMatterEdit(in: text, goal: newGoal) {
            editor.textView.applyKeepingSelection(edit)
            editor.textView.undoManager?.setActionName("Writing Goal")
        } else if let url = fileURL {
            WritingGoal.store(newGoal, for: url)
        } else {
            sessionGoal = newGoal
        }
        updateGoal(text: editor.text, previousWords: statistics.words)
    }

    // MARK: - Toasts

    struct Toast: Identifiable {
        let id = UUID()
        var message: String
        var systemImage: String
        var actionTitle: String?
        var action: (() -> Void)?
    }

    func showToast(_ message: String, systemImage: String = "info.circle", actionTitle: String? = nil, action: (() -> Void)? = nil) {
        let toast = Toast(message: message, systemImage: systemImage, actionTitle: actionTitle, action: action)
        self.toast = toast
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.toast?.id == toast.id { self?.toast = nil }
        }
    }

    func applyPreviewConfiguration(_ configuration: PreviewConfiguration) {
        previewConfiguration = configuration
        preview.configure(configuration)
    }

    // MARK: - Commands

    func perform(_ command: FormatCommand) {
        if viewMode == .preview { viewMode = .split }
        editor.perform(command)
    }

    func jump(toLine line: Int) {
        if viewMode.showsEditor { editor.reveal(line: line) }
        if viewMode.showsPreview { preview.reveal(line: line) }
    }

    func goToLine(_ oneBasedLine: Int) {
        if viewMode == .preview { viewMode = .split }
        let line = max(0, min(oneBasedLine - 1, editor.lineIndex.lineCount - 1))
        editor.reveal(line: line)
        if viewMode.showsPreview { preview.reveal(line: line) }
    }

    func zoomIn() { zoom = min(3, (zoom * 10 + 1).rounded() / 10) }
    func zoomOut() { zoom = max(0.5, (zoom * 10 - 1).rounded() / 10) }
    func resetZoom() { zoom = 1 }

    func toggleDistractionFree() {
        distractionFree.toggle()
        guard let window else { return }
        let isFullScreen = window.styleMask.contains(.fullScreen)
        if distractionFree != isFullScreen { window.toggleFullScreen(nil) }
        if distractionFree, viewMode == .split { viewMode = .editor }
    }

    // MARK: - Export

    private var exportSource: ExportService.Source {
        ExportService.Source(markdown: editor.text, title: title, documentURL: fileURL,
                             configuration: previewConfiguration, window: window)
    }

    func exportHTML() { Task { await ExportService.exportHTML(exportSource) } }
    func exportPDF() { Task { await ExportService.exportPDF(exportSource) } }
    func printDocument() { Task { await ExportService.print(exportSource) } }
    func copyHTML() { Task { await ExportService.copyHTML(exportSource) } }
    func copyRichText() { Task { await ExportService.copyRichText(exportSource) } }
}

extension FocusedValues {
    @Entry var session: DocumentSession?
}
