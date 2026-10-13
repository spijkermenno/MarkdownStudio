import AppKit

enum FormatCommand: Hashable {
    case bold, italic, strikethrough, highlight, inlineCode
    case link, image
    case heading(Int), cycleHeading
    case blockquote, bulletList, numberedList, taskList
    case codeBlock, horizontalRule, table, formatTable
    case indent, outdent
    case moveLinesUp, moveLinesDown, duplicateLines, renumberList, tableOfContents

    var actionName: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .highlight: "Highlight"
        case .inlineCode: "Code"
        case .link: "Insert Link"
        case .image: "Insert Image"
        case .heading(let level): level == 0 ? "Paragraph" : "Heading \(level)"
        case .cycleHeading: "Heading"
        case .blockquote: "Blockquote"
        case .bulletList: "Bulleted List"
        case .numberedList: "Numbered List"
        case .taskList: "Task List"
        case .codeBlock: "Code Block"
        case .horizontalRule: "Horizontal Rule"
        case .table: "Insert Table"
        case .formatTable: "Format Table"
        case .indent: "Indent"
        case .outdent: "Outdent"
        case .moveLinesUp: "Move Line Up"
        case .moveLinesDown: "Move Line Down"
        case .duplicateLines: "Duplicate Line"
        case .renumberList: "Renumber List"
        case .tableOfContents: "Table of Contents"
        }
    }
}

/// Owns the editor's AppKit views for one document window. The views outlive
/// SwiftUI view updates, so switching view modes keeps text, selection, undo
/// and scroll position.
final class EditorController: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
    let scrollView: NSScrollView
    let textView: MarkdownTextView
    private let ruler: LineNumberRulerView
    private let highlighter = MarkdownHighlighter()
    private(set) lazy var autocomplete = AutocompleteController(textView: textView)
    private(set) var lineIndex = LineIndex("")
    private(set) var configuration = EditorConfiguration()

    /// Clipboard HTML → Markdown, provided by the session (uses the preview's web view).
    var htmlConverter: ((String) async -> String?)? {
        didSet { textView.htmlConverter = configuration.pasteAsMarkdown ? htmlConverter : nil }
    }
    var onTextChange: ((String) -> Void)?
    var onSelectionChange: ((_ line: Int, _ column: Int, _ selectedLength: Int) -> Void)?
    /// Top visible source line (fractional) and whether the editor is scrolled to the end.
    var onScroll: ((_ line: Double, _ atBottom: Bool) -> Void)?

    private var isApplyingExternalScroll = false
    private var isSettingText = false
    private var isUpdatingTableOfContents = false
    private var pendingEditedRange: NSRange?

    var documentURL: URL? {
        get { textView.documentURL }
        set {
            textView.documentURL = newValue
            autocomplete.documentDirectory = newValue?.deletingLastPathComponent()
        }
    }

    init(text: String) {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500), textContainer: container)
        scrollView = NSScrollView()
        ruler = LineNumberRulerView(textView: textView)
        super.init()

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlAccentColor
        textView.allowsDocumentBackgroundColorChange = false
        textView.registerForDraggedTypes([.fileURL])
        textView.delegate = self
        storage.delegate = self

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.borderType = .noBorder
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        NotificationCenter.default.addObserver(self, selector: #selector(boundsDidChange(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(frameDidChange(_:)),
                                               name: NSView.frameDidChangeNotification, object: scrollView)

        configure(configuration, force: true)
        setText(text)
    }

    // MARK: - Configuration

    func configure(_ configuration: EditorConfiguration, force: Bool = false) {
        guard force || configuration != self.configuration else { return }
        let fontChanged = force || configuration.font != self.configuration.font
            || configuration.syntaxHighlighting != self.configuration.syntaxHighlighting
        self.configuration = configuration

        textView.autoPairing = configuration.autoPairing
        textView.smartLists = configuration.smartLists
        textView.highlightCurrentLine = configuration.highlightCurrentLine
        textView.isContinuousSpellCheckingEnabled = configuration.spellCheck
        textView.htmlConverter = configuration.pasteAsMarkdown ? htmlConverter : nil
        autocomplete.isEnabled = configuration.autocomplete
        if !configuration.autocomplete { autocomplete.hide() }
        scrollView.rulersVisible = configuration.showLineNumbers
        highlighter.configure(configuration)
        textView.typingAttributes = highlighter.baseAttributes
        ruler.textFont = configuration.font
        if fontChanged, let storage = textView.textStorage {
            // Setting `font` restyles the whole storage, so highlight afterwards.
            textView.font = configuration.font
            highlighter.highlightAll(storage)
        }
        updateTypewriterInset()
        updateFocusMode()
        ruler.needsDisplay = true
    }

    // MARK: - Text

    var text: String { textView.string }

    /// Replaces the whole text (document load or revert), keeping the selection where possible.
    func setText(_ text: String) {
        guard text != textView.string else { return }
        let selection = textView.selectedRange()
        let scrollOrigin = scrollView.contentView.bounds.origin
        isSettingText = true
        textView.string = text
        isSettingText = false
        lineIndex = LineIndex(text)
        ruler.lineIndex = lineIndex
        if let storage = textView.textStorage { highlighter.highlightAll(storage) }
        pendingEditedRange = nil
        let length = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        // Keep the reader's place when the file is reloaded.
        scrollView.contentView.scroll(to: scrollOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateFocusMode()
    }

    func perform(_ command: FormatCommand) {
        let text = textView.string
        let selection = textView.selectedRange()
        let edit: TextEdit?
        switch command {
        case .bold: edit = MarkdownEditing.toggleWrap(text, selection: selection, marker: "**")
        case .italic: edit = MarkdownEditing.toggleWrap(text, selection: selection, marker: "*")
        case .strikethrough: edit = MarkdownEditing.toggleWrap(text, selection: selection, marker: "~~")
        case .highlight: edit = MarkdownEditing.toggleWrap(text, selection: selection, marker: "==")
        case .inlineCode: edit = MarkdownEditing.toggleWrap(text, selection: selection, marker: "`")
        case .link, .image:
            let clipboard = NSPasteboard.general.string(forType: .string)
            edit = MarkdownEditing.insertLink(text, selection: selection, image: command == .image, clipboardURL: clipboard)
        case .heading(let level): edit = MarkdownEditing.setHeading(text, selection: selection, level: level)
        case .cycleHeading: edit = MarkdownEditing.cycleHeading(text, selection: selection)
        case .blockquote: edit = MarkdownEditing.toggleBlockquote(text, selection: selection)
        case .bulletList: edit = MarkdownEditing.toggleList(text, selection: selection, kind: .bullet)
        case .numberedList: edit = MarkdownEditing.toggleList(text, selection: selection, kind: .numbered)
        case .taskList: edit = MarkdownEditing.toggleList(text, selection: selection, kind: .task)
        case .codeBlock: edit = MarkdownEditing.toggleCodeBlock(text, selection: selection)
        case .horizontalRule: edit = MarkdownEditing.insertHorizontalRule(text, selection: selection)
        case .table: edit = MarkdownEditing.insertTable(text, selection: selection)
        case .formatTable: edit = TableFormatter.formatTable(text, at: selection.location)
        case .indent: edit = MarkdownEditing.indent(text, selection: selection)
        case .outdent: edit = MarkdownEditing.outdent(text, selection: selection)
        case .moveLinesUp: edit = MarkdownEditing.moveLines(text, selection: selection, up: true)
        case .moveLinesDown: edit = MarkdownEditing.moveLines(text, selection: selection, up: false)
        case .duplicateLines: edit = MarkdownEditing.duplicateLines(text, selection: selection)
        case .renumberList:
            edit = MarkdownEditing.renumberList(text, line: lineIndex.line(containing: selection.location), selection: selection)
        case .tableOfContents: edit = TableOfContents.insert(text, selection: selection)
        }
        guard let edit else {
            NSSound.beep()
            return
        }
        textView.apply(edit, actionName: command.actionName)
        if command == .moveLinesUp || command == .moveLinesDown {
            // Keep both the list the lines left and the one they joined numbered.
            textView.renumberList(at: edit.range.location)
            textView.renumberList(at: textView.selectedRange().location)
        }
        textView.window?.makeFirstResponder(textView)
    }

    func toggleTask(atLine line: Int) {
        guard let edit = MarkdownEditing.toggleTask(textView.string, line: line) else { return }
        let selection = textView.selectedRange()
        textView.apply(edit, actionName: "Toggle Task")
        textView.setSelectedRange(selection)
    }

    // MARK: - NSTextStorageDelegate / NSTextViewDelegate

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        if editedMask.contains(.editedCharacters) {
            pendingEditedRange = pendingEditedRange.map { NSUnionRange($0, editedRange) } ?? editedRange
        }
    }

    func textDidChange(_ notification: Notification) {
        guard !isSettingText else { return }
        let text = textView.string
        lineIndex = LineIndex(text)
        ruler.lineIndex = lineIndex
        if let storage = textView.textStorage, let edited = pendingEditedRange {
            let clamped = NSIntersectionRange(edited, NSRange(location: 0, length: storage.length))
            highlighter.highlightEdit(storage, editedRange: clamped.location == NSNotFound ? NSRange(location: storage.length, length: 0) : clamped)
        }
        pendingEditedRange = nil
        // Keep a table of contents in sync with the headings. The update joins
        // the same undo step as the edit that caused it, and its nested
        // textDidChange reports the final text.
        let undoManager = textView.undoManager
        let replayingUndo = undoManager?.isUndoing == true || undoManager?.isRedoing == true
        if !isUpdatingTableOfContents, !replayingUndo, let edit = TableOfContents.update(text) {
            isUpdatingTableOfContents = true
            textView.applyKeepingSelection(edit)
            isUpdatingTableOfContents = false
            return
        }
        onTextChange?(text)
        if textView.lastChangeWasTyping {
            textView.lastChangeWasTyping = false
            autocomplete.update()
        } else {
            autocomplete.hide()
        }
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        autocomplete.handle(commandSelector)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        let selection = textView.selectedRange()
        let line = lineIndex.line(containing: selection.location)
        let column = selection.location - lineIndex.start(ofLine: line)
        onSelectionChange?(line, column, selection.length)
        if autocomplete.isVisible, !textView.lastChangeWasTyping {
            // Clicking or arrowing away closes the list; typing keeps it updated.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.textView.lastChangeWasTyping else { return }
                if CompletionEngine.context(in: self.textView.string, caret: self.textView.selectedRange().location) == nil {
                    self.autocomplete.hide()
                }
            }
        }
        ruler.needsDisplay = true
        updateFocusMode()
        if configuration.typewriterScrolling { centerCaret() }
    }

    // MARK: - Scrolling

    @objc private func boundsDidChange(_ notification: Notification) {
        ruler.needsDisplay = true
        guard !isApplyingExternalScroll else { return }
        onScroll?(topVisibleLine(), isAtBottom)
    }

    @objc private func frameDidChange(_ notification: Notification) {
        updateTypewriterInset()
    }

    private var isAtBottom: Bool {
        let clip = scrollView.contentView
        guard let document = scrollView.documentView else { return false }
        return clip.bounds.maxY >= document.frame.height - 2 && document.frame.height > clip.bounds.height + 2
    }

    func topVisibleLine() -> Double {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return 0 }
        let y = scrollView.contentView.bounds.minY - textView.textContainerOrigin.y + Self.syncMargin
        guard scrollView.contentView.bounds.minY > 0, layoutManager.numberOfGlyphs > 0 else { return 0 }
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: y), in: container)
        let char = layoutManager.characterIndexForGlyph(at: glyph)
        let line = lineIndex.line(containing: char)
        let rect = rect(forLine: line)
        let fraction = rect.height > 0 ? min(1, max(0, (y - rect.minY) / rect.height)) : 0
        return Double(line) + fraction
    }

    /// How far below the top edge the synced line sits, like the preview's top padding.
    private static let syncMargin: CGFloat = 16

    /// Bounding rect of a source line in text-container coordinates.
    private func rect(forLine line: Int) -> NSRect {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return .zero }
        let range = lineIndex.range(ofLine: line)
        if range.length == 0 || range.location >= (textView.string as NSString).length {
            return layoutManager.extraLineFragmentRect
        }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
    }

    /// Scrolls so that the (fractional) source line is at the top; used by scroll sync.
    func scroll(toLine line: Double, atBottom: Bool) {
        isApplyingExternalScroll = true
        defer { isApplyingExternalScroll = false }
        let clip = scrollView.contentView
        let y: CGFloat
        if atBottom {
            y = max(0, (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height)
        } else {
            let whole = Int(line.rounded(.down))
            let rect = rect(forLine: whole)
            // Inverse of topVisibleLine(): the line sits `syncMargin` below the top edge.
            y = line <= 0 ? 0 : max(0, rect.minY + CGFloat(line - Double(whole)) * rect.height + textView.textContainerOrigin.y - Self.syncMargin)
        }
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    /// Selects a line, scrolls it to the upper third and focuses the editor.
    func reveal(line: Int, select: Bool = true) {
        let ns = textView.string as NSString
        let start = lineIndex.start(ofLine: line)
        let content = ns.lineContentRange(at: min(start, ns.length))
        textView.setSelectedRange(select ? NSRange(location: content.location, length: 0) : textView.selectedRange())
        let rect = rect(forLine: line)
        let clip = scrollView.contentView
        let y = max(0, rect.minY + textView.textContainerOrigin.y - clip.bounds.height / 3)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(clip)
        textView.window?.makeFirstResponder(textView)
        textView.showFindIndicator(for: content.length > 0 ? content : NSRange(location: content.location, length: 0))
    }

    // MARK: - Document check

    /// Dotted underlines under problem ranges (warnings orange, notes blue).
    func showProblems(_ problems: [DocumentProblem]) {
        guard let layoutManager = textView.layoutManager else { return }
        let length = (textView.string as NSString).length
        // Underlines move with edits, so clear them everywhere rather than at remembered ranges.
        let all = NSRange(location: 0, length: length)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: all)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: all)
        let style = NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue
        for problem in problems {
            let range = NSIntersectionRange(problem.range, NSRange(location: 0, length: length))
            guard range.length > 0 else { continue }
            layoutManager.addTemporaryAttributes([
                .underlineStyle: style,
                .underlineColor: problem.severity == .warning ? NSColor.systemOrange : NSColor.systemBlue,
            ], forCharacterRange: range)
        }
    }

    /// Selects a range and scrolls it into view.
    func select(_ range: NSRange) {
        let length = (textView.string as NSString).length
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: length))
        reveal(line: lineIndex.line(containing: clamped.location), select: false)
        textView.setSelectedRange(clamped)
    }

    /// Applies a quick fix from the document check.
    func apply(_ edit: TextEdit, actionName: String) {
        textView.apply(edit, actionName: actionName)
        textView.window?.makeFirstResponder(textView)
    }

    // MARK: - Typewriter scrolling & focus mode

    private func updateTypewriterInset() {
        let vertical: CGFloat = configuration.typewriterScrolling ? max(16, scrollView.contentView.bounds.height / 2) : 16
        if textView.textContainerInset.height != vertical {
            textView.textContainerInset = NSSize(width: 18, height: vertical)
        }
        if configuration.typewriterScrolling { centerCaret() }
    }

    private func centerCaret() {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        let location = textView.selectedRange().location
        let rect: NSRect
        if location >= (textView.string as NSString).length && layoutManager.extraLineFragmentRect.height > 0 {
            rect = layoutManager.extraLineFragmentRect
        } else {
            let glyph = layoutManager.glyphIndexForCharacter(at: min(location, max(0, (textView.string as NSString).length - 1)))
            rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 0), in: container)
        }
        let clip = scrollView.contentView
        let y = rect.midY + textView.textContainerOrigin.y - clip.bounds.height / 2
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: max(0, y)))
        scrollView.reflectScrolledClipView(clip)
    }

    /// Dims everything except the paragraph containing the caret.
    private func updateFocusMode() {
        guard let layoutManager = textView.layoutManager else { return }
        let ns = textView.string as NSString
        let all = NSRange(location: 0, length: ns.length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
        guard configuration.focusMode, ns.length > 0 else { return }
        let focus = Self.paragraphRange(in: ns, at: textView.selectedRange().location)
        let dim = NSColor.tertiaryLabelColor
        if focus.location > 0 {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: dim, forCharacterRange: NSRange(location: 0, length: focus.location))
        }
        if NSMaxRange(focus) < ns.length {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: dim,
                                                forCharacterRange: NSRange(location: NSMaxRange(focus), length: ns.length - NSMaxRange(focus)))
        }
    }

    /// The block between blank lines around `location`.
    static func paragraphRange(in ns: NSString, at location: Int) -> NSRange {
        func isBlank(_ range: NSRange) -> Bool {
            ns.substring(with: range).trimmingCharacters(in: .whitespaces).isEmpty
        }
        var start = ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
        var end = start
        if isBlank(ns.lineContentRange(at: start.location)) { return start }
        while start.location > 0 {
            let previous = ns.lineRange(for: NSRange(location: start.location - 1, length: 0))
            if isBlank(ns.lineContentRange(at: previous.location)) { break }
            start = previous
        }
        while NSMaxRange(end) < ns.length {
            let next = ns.lineRange(for: NSRange(location: NSMaxRange(end), length: 0))
            if isBlank(ns.lineContentRange(at: next.location)) { break }
            end = next
        }
        return NSRange(location: start.location, length: NSMaxRange(end) - start.location)
    }
}
