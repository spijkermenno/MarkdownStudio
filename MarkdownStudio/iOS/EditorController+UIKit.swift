#if os(iOS)
import UIKit

/// Owns the editor's UIKit text view for one document scene. Like the Mac
/// version, the view outlives SwiftUI updates, so switching view modes keeps
/// text, selection, undo and scroll position.
final class EditorController: NSObject, UITextViewDelegate, NSTextStorageDelegate {
    let textView: MarkdownTextView
    private let layoutManager = EditorLayoutManager()
    private let highlighter = MarkdownHighlighter()
    private lazy var gutter = LineNumberGutterView(textView: textView)
    private let accessoryModel = EditorAccessoryModel()
    private lazy var accessoryView = EditorAccessoryView(model: accessoryModel)
    private(set) lazy var autocomplete = AutocompleteController(textView: textView, model: accessoryModel)
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
    /// The keyboard came up or went away.
    var onEditingChange: ((Bool) -> Void)?
    /// A button in the formatting bar above the keyboard was tapped.
    var onFormat: ((FormatCommand) -> Void)? {
        didSet { accessoryModel.onFormat = onFormat }
    }
    /// Shows the formatting bar above the keyboard.
    var showsFormattingBar = true {
        didSet { if showsFormattingBar != oldValue { updateAccessory() } }
    }

    private var isApplyingExternalScroll = false
    private var isSettingText = false
    private var isUpdatingTableOfContents = false
    private var pendingEditedRange: NSRange?
    /// Set when the storage's characters changed and the change hasn't been processed yet.
    private var needsChangeProcessing = false
    private var lastBoundsSize = CGSize.zero

    var documentURL: URL? {
        get { textView.documentURL }
        set {
            textView.documentURL = newValue
            // On iOS the app may only be allowed to read the document itself.
            let directory = newValue?.deletingLastPathComponent()
            autocomplete.documentDirectory = directory.flatMap { (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) != nil ? $0 : nil }
        }
    }

    init(text: String) {
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        // An explicit container keeps the text view on TextKit 1, like the Mac editor.
        textView = MarkdownTextView(frame: CGRect(x: 0, y: 0, width: 500, height: 500), textContainer: container)
        super.init()

        textView.autocapitalizationType = .sentences
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.dataDetectorTypes = []
        textView.allowsEditingTextAttributes = false
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.backgroundColor = .systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        textView.isFindInteractionEnabled = true
        textView.delegate = self
        storage.delegate = self
        textView.addSubview(gutter)
        gutter.isHidden = true
        textView.onEdit = { [weak self] in self?.textDidChange() }
        textView.onLayout = { [weak self] in self?.textViewDidLayout() }
        accessoryModel.onDismissKeyboard = { [weak self] in self?.textView.resignFirstResponder() }
        autocomplete.onVisibilityChange = { [weak self] in self?.updateAccessory() }

        configure(configuration, force: true)
        setText(text)
        updateAccessory()
    }

    // MARK: - Configuration

    func configure(_ configuration: EditorConfiguration, force: Bool = false) {
        guard force || configuration != self.configuration else { return }
        let fontChanged = force || configuration.font != self.configuration.font
            || configuration.syntaxHighlighting != self.configuration.syntaxHighlighting
        self.configuration = configuration

        textView.autoPairing = configuration.autoPairing
        textView.smartLists = configuration.smartLists
        // Autocorrection follows the keyboard settings unless spell checking is off.
        textView.spellCheckingType = configuration.spellCheck ? .yes : .no
        textView.autocorrectionType = configuration.spellCheck ? .default : .no
        textView.htmlConverter = configuration.pasteAsMarkdown ? htmlConverter : nil
        autocomplete.isEnabled = configuration.autocomplete
        autocomplete.fontSize = configuration.font.pointSize
        if !configuration.autocomplete { autocomplete.hide() }
        highlighter.configure(configuration)
        textView.typingAttributes = highlighter.baseAttributes
        gutter.textFont = configuration.font
        gutter.isHidden = !configuration.showLineNumbers
        if fontChanged {
            highlighter.highlightAll(textView.textStorage)
        }
        updateInsets()
        updateCurrentLine()
        updateFocusMode()
    }

    // MARK: - Text

    var text: String { textView.text }

    /// Replaces the whole text (document load or revert), keeping the selection where possible.
    func setText(_ text: String) {
        guard text != textView.text else { return }
        let selection = textView.selectedRange
        let offset = textView.contentOffset
        let isReplacing = !textView.text.isEmpty
        isSettingText = true
        textView.textStorage.setAttributedString(NSAttributedString(string: text, attributes: highlighter.baseAttributes))
        isSettingText = false
        needsChangeProcessing = false
        lineIndex = LineIndex(text)
        gutter.lineIndex = lineIndex
        highlighter.highlightAll(textView.textStorage)
        pendingEditedRange = nil
        // Undo steps recorded against the old text no longer apply.
        if isReplacing { textView.undoManager?.removeAllActions() }
        let length = (text as NSString).length
        textView.selectedRange = NSRange(location: min(selection.location, length), length: 0)
        // Keep the reader's place when the file is reloaded.
        textView.layoutIfNeeded()
        textView.contentOffset = CGPoint(x: offset.x, y: min(offset.y, max(-textView.adjustedContentInset.top, maxOffsetY)))
        updateGutter()
        updateFocusMode()
    }

    func perform(_ command: FormatCommand) {
        let text = textView.text ?? ""
        let selection = textView.selectedRange
        let edit: TextEdit?
        switch command {
        case .bold: edit = MarkdownEditing.toggleWrap(text, selection: selection, marker: "**")
        case .italic: edit = MarkdownEditing.toggleWrap(text, selection: selection, marker: "*")
        case .strikethrough: edit = MarkdownEditing.toggleWrap(text, selection: selection, marker: "~~")
        case .highlight: edit = MarkdownEditing.toggleWrap(text, selection: selection, marker: "==")
        case .inlineCode: edit = MarkdownEditing.toggleWrap(text, selection: selection, marker: "`")
        case .link, .image:
            edit = MarkdownEditing.insertLink(text, selection: selection, image: command == .image, clipboardURL: Platform.clipboardString)
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
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        textView.apply(edit, actionName: command.actionName)
        if command == .moveLinesUp || command == .moveLinesDown {
            // Keep both the list the lines left and the one they joined numbered.
            textView.renumberList(at: edit.range.location)
            textView.renumberList(at: textView.selectedRange.location)
        }
        textView.becomeFirstResponder()
    }

    func toggleTask(atLine line: Int) {
        guard let edit = MarkdownEditing.toggleTask(textView.text, line: line) else { return }
        let selection = textView.selectedRange
        textView.apply(edit, actionName: "Toggle Task")
        textView.selectedRange = selection
    }

    /// Inserts text at the caret as one undo step (templates, snippets).
    func insert(_ string: String, actionName: String) {
        let selection = textView.selectedRange
        textView.apply(TextEdit(range: selection, replacement: string, selection: NSRange(location: selection.location, length: 0)),
                       actionName: actionName)
        textView.setContentOffset(CGPoint(x: 0, y: -textView.adjustedContentInset.top), animated: false)
    }

    // MARK: - NSTextStorageDelegate / UITextViewDelegate

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        pendingEditedRange = pendingEditedRange.map { NSUnionRange($0, editedRange) } ?? editedRange
        guard !isSettingText else { return }
        // Undo and redo don't always report through the delegate, so catch
        // any change that wasn't processed by the end of this run loop turn.
        needsChangeProcessing = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.needsChangeProcessing else { return }
            self.textDidChange()
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        guard !isSettingText, !self.textView.isApplyingEdit else { return }
        textDidChange()
    }

    private func textDidChange() {
        needsChangeProcessing = false
        let text = textView.text ?? ""
        lineIndex = LineIndex(text)
        gutter.lineIndex = lineIndex
        let storage = textView.textStorage
        if let edited = pendingEditedRange {
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
        updateInsets()
        updateGutter()
        if textView.lastChangeWasTyping {
            textView.lastChangeWasTyping = false
            autocomplete.update()
        } else {
            autocomplete.hide()
        }
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        let selection = textView.selectedRange
        let line = lineIndex.line(containing: selection.location)
        let column = selection.location - lineIndex.start(ofLine: line)
        onSelectionChange?(line, column, selection.length)
        if autocomplete.isVisible, !self.textView.lastChangeWasTyping {
            // Tapping or arrowing away closes the list; typing keeps it updated.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.textView.lastChangeWasTyping else { return }
                if CompletionEngine.context(in: self.textView.text, caret: self.textView.selectedRange.location) == nil {
                    self.autocomplete.hide()
                }
            }
        }
        gutter.setNeedsDisplay()
        updateCurrentLine()
        updateFocusMode()
        if configuration.typewriterScrolling { centerCaret() }
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        updateCurrentLine()
        onEditingChange?(true)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        autocomplete.hide()
        updateCurrentLine()
        onEditingChange?(false)
    }

    // MARK: - Keyboard bar

    /// The bar shows the formatting buttons when they're turned on, and
    /// suggestions whenever there are some.
    private func updateAccessory() {
        let wanted: UIView? = showsFormattingBar || autocomplete.isVisible ? accessoryView : nil
        guard textView.inputAccessoryView !== wanted else { return }
        textView.inputAccessoryView = wanted
        if textView.isFirstResponder { textView.reloadInputViews() }
    }

    // MARK: - Scrolling

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateGutter()
        guard !isApplyingExternalScroll else { return }
        onScroll?(topVisibleLine(), isAtBottom)
    }

    private func textViewDidLayout() {
        updateGutter()
        if textView.bounds.size != lastBoundsSize {
            lastBoundsSize = textView.bounds.size
            updateInsets()
        }
    }

    private var maxOffsetY: CGFloat {
        textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom
    }

    private var visibleTop: CGFloat {
        textView.contentOffset.y + textView.adjustedContentInset.top
    }

    private var isAtBottom: Bool {
        let visibleHeight = textView.bounds.height - textView.adjustedContentInset.top - textView.adjustedContentInset.bottom
        return textView.contentOffset.y >= maxOffsetY - 2 && textView.contentSize.height > visibleHeight + 2
    }

    func topVisibleLine() -> Double {
        let y = visibleTop - textView.textContainerInset.top + Self.syncMargin
        guard visibleTop > 0, layoutManager.numberOfGlyphs > 0 else { return 0 }
        let glyph = layoutManager.glyphIndex(for: CGPoint(x: 0, y: y), in: textView.textContainer)
        let char = layoutManager.characterIndexForGlyph(at: glyph)
        let line = lineIndex.line(containing: char)
        let rect = rect(forLine: line)
        let fraction = rect.height > 0 ? min(1, max(0, (y - rect.minY) / rect.height)) : 0
        return Double(line) + fraction
    }

    /// How far below the top edge the synced line sits, like the preview's top padding.
    private static let syncMargin: CGFloat = 16

    /// Bounding rect of a source line in text-container coordinates.
    private func rect(forLine line: Int) -> CGRect {
        let range = lineIndex.range(ofLine: line)
        if range.length == 0 || range.location >= (textView.text as NSString).length {
            if range.location < (textView.text as NSString).length {
                let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
                return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            return layoutManager.extraLineFragmentRect
        }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return layoutManager.boundingRect(forGlyphRange: glyphs, in: textView.textContainer)
    }

    private func scroll(toY y: CGFloat) {
        let top = -textView.adjustedContentInset.top
        textView.contentOffset = CGPoint(x: textView.contentOffset.x, y: min(max(top, y), max(top, maxOffsetY)))
    }

    /// Scrolls so that the (fractional) source line is at the top; used by scroll sync.
    func scroll(toLine line: Double, atBottom: Bool) {
        isApplyingExternalScroll = true
        defer { isApplyingExternalScroll = false }
        if atBottom {
            scroll(toY: maxOffsetY)
        } else if line <= 0 {
            scroll(toY: -textView.adjustedContentInset.top)
        } else {
            let whole = Int(line.rounded(.down))
            let rect = rect(forLine: whole)
            // Inverse of topVisibleLine(): the line sits `syncMargin` below the top edge.
            let y = rect.minY + CGFloat(line - Double(whole)) * rect.height + textView.textContainerInset.top - Self.syncMargin
            scroll(toY: y - textView.adjustedContentInset.top)
        }
    }

    /// Selects a line and scrolls it to the upper third. Unlike the Mac, this
    /// doesn't bring up the keyboard: on a phone it would cover what you jumped to.
    func reveal(line: Int, select: Bool = true) {
        let ns = textView.text as NSString
        let start = lineIndex.start(ofLine: line)
        let content = ns.lineContentRange(at: min(start, ns.length))
        if select { textView.selectedRange = NSRange(location: content.location, length: 0) }
        textView.layoutIfNeeded()
        let rect = rect(forLine: line)
        let visibleHeight = textView.bounds.height - textView.adjustedContentInset.top - textView.adjustedContentInset.bottom
        scroll(toY: rect.minY + textView.textContainerInset.top - visibleHeight / 3 - textView.adjustedContentInset.top)
    }

    // MARK: - Document check

    func showProblems(_ problems: [DocumentProblem]) {
        layoutManager.problems = problems
        let length = textView.textStorage.length
        layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: length))
    }

    /// Selects a range and scrolls it into view.
    func select(_ range: NSRange) {
        let length = (textView.text as NSString).length
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: length))
        reveal(line: lineIndex.line(containing: clamped.location), select: false)
        textView.selectedRange = clamped
    }

    /// Applies a quick fix from the document check.
    func apply(_ edit: TextEdit, actionName: String) {
        textView.apply(edit, actionName: actionName)
    }

    // MARK: - Line numbers, typewriter scrolling & focus mode

    private func updateGutter() {
        guard !gutter.isHidden else { return }
        gutter.follow()
        textView.bringSubviewToFront(gutter)
    }

    private func updateInsets() {
        let left = 18 + (configuration.showLineNumbers ? gutter.width : 0)
        let vertical: CGFloat = configuration.typewriterScrolling ? max(16, textView.bounds.height / 2) : 16
        let insets = UIEdgeInsets(top: vertical, left: left, bottom: vertical, right: 18)
        if textView.textContainerInset != insets {
            textView.textContainerInset = insets
            updateGutter()
        }
        if configuration.typewriterScrolling { centerCaret() }
    }

    private func centerCaret() {
        guard let position = textView.selectedTextRange?.end else { return }
        let caret = textView.caretRect(for: position)
        guard !caret.isNull, !caret.isInfinite else { return }
        let visibleHeight = textView.bounds.height - textView.adjustedContentInset.top - textView.adjustedContentInset.bottom
        scroll(toY: caret.midY - visibleHeight / 2 - textView.adjustedContentInset.top)
    }

    /// Like the Mac, only while the editor has the keyboard focus.
    private func updateCurrentLine() {
        let old = layoutManager.currentLineRect
        var new: CGRect?
        if configuration.highlightCurrentLine, textView.isFirstResponder, textView.selectedRange.length == 0 {
            let ns = textView.text as NSString
            let location = textView.selectedRange.location
            if location >= ns.length, ns.length == 0 || ns.character(at: ns.length - 1) == 0x0A {
                new = layoutManager.extraLineFragmentRect
            } else {
                let line = ns.lineContentRange(at: min(location, ns.length))
                let glyphs = layoutManager.glyphRange(forCharacterRange: line, actualCharacterRange: nil)
                new = glyphs.length > 0
                    ? layoutManager.boundingRect(forGlyphRange: glyphs, in: textView.textContainer)
                    : layoutManager.lineFragmentRect(forGlyphAt: min(glyphs.location, max(0, layoutManager.numberOfGlyphs - 1)), effectiveRange: nil)
            }
            if new?.isEmpty == true { new = nil }
        }
        guard old != new else { return }
        layoutManager.currentLineRect = new
        for rect in [old, new].compactMap({ $0 }) {
            let glyphs = layoutManager.glyphRange(forBoundingRect: rect, in: textView.textContainer)
            layoutManager.invalidateDisplay(forGlyphRange: glyphs)
        }
        if old == nil || new == nil {
            // Empty lines have no glyphs to invalidate.
            textView.setNeedsDisplay()
            textView.subviews.forEach { $0.setNeedsDisplay() }
        }
    }

    /// Dims everything except the paragraph containing the caret.
    private func updateFocusMode() {
        let ns = textView.text as NSString
        let focus: NSRange? = configuration.focusMode && ns.length > 0
            ? EditorController.paragraphRange(in: ns, at: textView.selectedRange.location)
            : nil
        guard focus != layoutManager.focusRange else { return }
        layoutManager.focusRange = focus
        layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: ns.length))
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
#endif
