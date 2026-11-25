#if os(iOS)
import UIKit
import UniformTypeIdentifiers

/// The editor's text view on iPhone and iPad: smart lists, auto-pairing,
/// Markdown-aware paste and hardware keyboard shortcuts.
final class MarkdownTextView: UITextView {
    var autoPairing = true
    var smartLists = true

    /// The document's folder, used to make pasted files relative.
    var documentURL: URL?

    /// Converts clipboard HTML to Markdown; nil disables conversion.
    var htmlConverter: ((String) async -> String?)?
    /// Called after a paste was converted, so the UI can offer Undo.
    var onPasteConverted: (() -> Void)?
    /// Set by typing (and Delete), read by the autocomplete after the change.
    var lastChangeWasTyping = false

    /// Called after every edit made through `apply`, in place of the delegate's
    /// `textViewDidChange` (which UIKit only sends for keyboard input).
    var onEdit: (() -> Void)?
    var onError: ((String) -> Void)?
    var onLayout: (() -> Void)?

    /// The suggestion list is open: Return, Tab, the arrow keys and Escape go to it.
    var isShowingSuggestions = false
    var onSuggestionKey: ((SuggestionKey) -> Bool)?

    enum SuggestionKey { case up, down, accept, cancel }

    /// The document's undo manager (from SwiftUI). Edits registered with it
    /// mark the document as changed, which is what makes it save.
    weak var documentUndoManager: UndoManager?
    override var undoManager: UndoManager? { documentUndoManager ?? super.undoManager }

    private(set) var isApplyingEdit = false

    private static let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "`": "`"]
    private static let wrapOnly: Set<String> = ["*", "_", "~", "=", "\"", "<"]
    private static let closers: Set<String> = [")", "]", "}", "`"]

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    // MARK: - Editing helpers

    /// Replaces text in the storage and registers the undo step itself. Going
    /// through UIKit's text input instead would apply smart punctuation to
    /// the replacement (`---` front matter became an em dash).
    private func replaceCharacters(in range: NSRange, with string: String) {
        let ns = text as NSString
        guard NSMaxRange(range) <= ns.length else { return }
        let replaced = ns.substring(with: range)
        let selectionBefore = selectedRange
        inputDelegate?.textWillChange(self)
        isApplyingEdit = true
        textStorage.replaceCharacters(in: range, with: NSAttributedString(string: string, attributes: typingAttributes))
        isApplyingEdit = false
        inputDelegate?.textDidChange(self)
        // Undo restores the old text and selection. It goes through this method
        // too, so it registers the redo step.
        let inserted = NSRange(location: range.location, length: string.utf16Length)
        undoManager?.registerUndo(withTarget: self) { view in
            view.replaceCharacters(in: inserted, with: replaced)
            view.selectedRange = selectionBefore
        }
        onEdit?()
    }

    /// Performs an edit so it is undoable.
    func apply(_ edit: TextEdit, actionName: String? = nil) {
        replaceCharacters(in: edit.range, with: edit.replacement)
        if let actionName { undoManager?.setActionName(actionName) }
        let length = (text as NSString).length
        let selection = NSRange(location: min(edit.selection.location, length),
                                length: min(edit.selection.length, max(0, length - edit.selection.location)))
        selectedRange = selection
        scrollRangeToVisible(selection)
    }

    /// Applies an edit made on the user's behalf without moving their caret
    /// (other than shifting it when text before it changed length).
    func applyKeepingSelection(_ edit: TextEdit) {
        let selection = selectedRange
        replaceCharacters(in: edit.range, with: edit.replacement)
        let delta = edit.replacement.utf16Length - edit.range.length
        var location = selection.location
        if edit.range.location < selection.location {
            location = NSMaxRange(edit.range) <= selection.location ? selection.location + delta : edit.range.location
        }
        let length = (text as NSString).length
        selectedRange = NSRange(location: min(max(0, location), length),
                                length: min(selection.length, max(0, length - location)))
    }

    /// Renumbers the ordered list around `location`, if there is one.
    func renumberList(at location: Int) {
        guard smartLists else { return }
        let line = LineIndex(text).line(containing: min(location, (text as NSString).length))
        if let edit = MarkdownEditing.renumberList(text, line: line, selection: selectedRange) {
            apply(edit)
        }
    }

    // MARK: - Smart typing

    override func insertText(_ string: String) {
        // Return and Tab pick a suggestion while the list is open
        // (with VoiceOver, Return always starts a new line).
        if isShowingSuggestions, markedTextRange == nil,
           string == "\t" || (string == "\n" && !AccessibilitySupport.isVoiceOverRunning),
           onSuggestionKey?(.accept) == true {
            return
        }
        lastChangeWasTyping = true
        guard markedTextRange == nil else { return super.insertText(string) }
        switch string {
        case "\n": insertNewline()
        case "\t": insertTab()
        default:
            if autoPairing, string.utf16.count == 1, insertPaired(string) { return }
            super.insertText(string)
        }
    }

    private func insertNewline() {
        if smartLists, let edit = MarkdownEditing.newline(text, selection: selectedRange) {
            apply(edit)
            renumberList(at: selectedRange.location)
            return
        }
        super.insertText("\n")
    }

    private func insertTab() {
        let selection = selectedRange
        let multiline = (text as NSString).substring(with: selection).contains("\n")
        if smartLists && (multiline || MarkdownEditing.isListLine(text, at: selection.location)) {
            apply(MarkdownEditing.indent(text, selection: selection), actionName: "Indent")
            return
        }
        super.insertText(MarkdownEditing.indentUnit)
    }

    @objc func outdent() {
        apply(MarkdownEditing.outdent(text, selection: selectedRange), actionName: "Outdent")
    }

    /// Auto-pairing; returns false when the character should be typed as-is.
    private func insertPaired(_ typed: String) -> Bool {
        let ns = text as NSString
        let selection = selectedRange
        let next = selection.location < ns.length ? ns.substring(with: NSRange(location: selection.location, length: 1)) : ""
        let previous = selection.location > 0 ? ns.substring(with: NSRange(location: selection.location - 1, length: 1)) : ""

        // Wrap a selection: typing * around "word" gives *word*.
        if selection.length > 0, let close = Self.pairs[typed] ?? (Self.wrapOnly.contains(typed) ? (typed == "<" ? ">" : typed) : nil) {
            let selected = ns.substring(with: selection)
            apply(TextEdit(range: selection, replacement: typed + selected + close,
                           selection: NSRange(location: selection.location + 1, length: selection.length)))
            return true
        }

        // Step over an auto-inserted closing character.
        if selection.length == 0, Self.closers.contains(typed), next == typed {
            // Only the caret moves, so no text change will consume the typing flag.
            lastChangeWasTyping = false
            selectedRange = NSRange(location: selection.location + 1, length: 0)
            return true
        }

        // Insert a pair when the caret is not directly before a word.
        if selection.length == 0, let close = Self.pairs[typed] {
            let nextIsFree = next.isEmpty || next.rangeOfCharacter(from: .whitespacesAndNewlines) != nil || Self.closers.contains(next)
            // A backtick after another backtick (fence) or a word (closing a span) is typed as-is.
            let closesBacktick = typed == "`" && (previous == "`" || previous.rangeOfCharacter(from: .alphanumerics) != nil)
            if nextIsFree && !closesBacktick {
                apply(TextEdit(range: selection, replacement: typed + close,
                               selection: NSRange(location: selection.location + 1, length: 0)))
                return true
            }
        }
        return false
    }

    override func deleteBackward() {
        lastChangeWasTyping = true
        let selection = selectedRange
        let ns = text as NSString
        // Joining or removing lines inside an ordered list renumbers it afterwards.
        let removesLineBreak = selection.length > 0
            ? ns.substring(with: selection).contains("\n")
            : selection.location > 0 && ns.character(at: selection.location - 1) == 0x0A
        defer { if removesLineBreak { renumberList(at: selectedRange.location) } }
        if autoPairing, markedTextRange == nil, selection.length == 0, selection.location > 0, selection.location < ns.length {
            let previous = ns.substring(with: NSRange(location: selection.location - 1, length: 1))
            let next = ns.substring(with: NSRange(location: selection.location, length: 1))
            if let close = Self.pairs[previous], close == next {
                apply(TextEdit(range: NSRange(location: selection.location - 1, length: 2), replacement: "",
                               selection: NSRange(location: selection.location - 1, length: 0)))
                return
            }
        }
        super.deleteBackward()
    }

    // MARK: - Hardware keyboard

    override var keyCommands: [UIKeyCommand]? {
        var commands = [UIKeyCommand(title: "Outdent", action: #selector(outdent), input: "\t", modifierFlags: .shift)]
        if isShowingSuggestions {
            let keys: [(String, Selector)] = [
                (UIKeyCommand.inputUpArrow, #selector(suggestionUp)),
                (UIKeyCommand.inputDownArrow, #selector(suggestionDown)),
                (UIKeyCommand.inputEscape, #selector(suggestionCancel)),
            ]
            for (input, action) in keys {
                let command = UIKeyCommand(input: input, modifierFlags: [], action: action)
                command.wantsPriorityOverSystemBehavior = true
                commands.append(command)
            }
        }
        return commands
    }

    @objc private func suggestionUp() { _ = onSuggestionKey?(.up) }
    @objc private func suggestionDown() { _ = onSuggestionKey?(.down) }
    @objc private func suggestionCancel() { _ = onSuggestionKey?(.cancel) }

    /// ⌘B, ⌘I and ⌘U come from the Format menu (Markdown), not rich-text styling.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(toggleBoldface(_:)) || action == #selector(toggleItalics(_:)) || action == #selector(toggleUnderline(_:)) {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }

    // MARK: - Paste

    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general
        let selection = selectedRange

        // Pasting a URL over selected text creates a link.
        if selection.length > 0, let pasted = pasteboard.string, MarkdownEditing.looksLikeURL(pasted) {
            let selected = (text as NSString).substring(with: selection)
            if !MarkdownEditing.looksLikeURL(selected) {
                apply(MarkdownEditing.insertLink(text, selection: selection, clipboardURL: pasted), actionName: "Paste Link")
                return
            }
        }

        // Pasting an image saves it next to the document.
        if !pasteboard.hasStrings, !pasteboard.hasURLs, let image = pasteboard.image {
            pasteImage(image)
            return
        }

        if let urls = pasteboard.urls?.filter(\.isFileURL), !urls.isEmpty {
            insertLinks(to: urls, at: selection)
            return
        }

        // Rich text from browsers, Google Docs, Word or Notion becomes Markdown.
        if let converter = htmlConverter, let html = Self.html(on: pasteboard), Self.isRichHTML(html) {
            let plain = pasteboard.string
            let textBefore = text
            Task { @MainActor [weak self] in
                guard let self else { return }
                let markdown = await converter(html)
                // If the text changed while converting, paste at the current selection instead.
                let range = self.text == textBefore ? selection : self.selectedRange
                guard let markdown, !markdown.isEmpty else {
                    if let plain { self.apply(TextEdit(range: range, replacement: plain,
                                                       selection: NSRange(location: range.location + plain.utf16Length, length: 0))) }
                    return
                }
                self.apply(TextEdit(range: range, replacement: markdown,
                                    selection: NSRange(location: range.location + markdown.utf16Length, length: 0)),
                           actionName: "Paste")
                if markdown != plain?.trimmingCharacters(in: .whitespacesAndNewlines) { self.onPasteConverted?() }
            }
            return
        }
        super.paste(sender)
    }

    /// Edit → Paste as Plain Text: the clipboard's text, without conversion.
    func pasteAsPlainText(_ sender: Any?) {
        guard let plain = UIPasteboard.general.string else { return }
        let range = selectedRange
        apply(TextEdit(range: range, replacement: plain,
                       selection: NSRange(location: range.location + plain.utf16Length, length: 0)),
              actionName: "Paste")
    }

    /// Edit → Paste and Match Style (⌥⇧⌘V) pastes the plain text, like the Mac's Paste as Plain Text.
    override func pasteAndMatchStyle(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    private static func html(on pasteboard: UIPasteboard) -> String? {
        let type = UTType.html.identifier
        if let string = pasteboard.value(forPasteboardType: type) as? String { return string }
        return pasteboard.data(forPasteboardType: type).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func pasteImage(_ image: UIImage) {
        guard let documentURL else {
            onError?("Save the document first: pasted images are saved in an “assets” folder next to it.")
            return
        }
        guard let png = image.pngData() else { return }
        let folder = documentURL.deletingLastPathComponent().appendingPathComponent("assets", isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = documentURL.deletingPathExtension().lastPathComponent
        var file = folder.appendingPathComponent("\(base)-\(formatter.string(from: Date())).png")
        var counter = 2
        while FileManager.default.fileExists(atPath: file.path) {
            file = folder.appendingPathComponent("\(base)-\(formatter.string(from: Date()))-\(counter).png")
            counter += 1
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: file)
            insertLinks(to: [file], at: selectedRange)
        } catch {
            // Outside the app's own folders, iOS only lets the app write the document itself.
            onError?("Couldn't save the image next to the document. Move the document to Markdown Studio's folder in Files to paste images.")
        }
    }

    private func insertLinks(to urls: [URL], at range: NSRange) {
        let markdown = urls.map { url -> String in
            let path = MarkdownPaths.relativePath(to: url, from: documentURL?.deletingLastPathComponent())
            let name = url.deletingPathExtension().lastPathComponent
            let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
            return isImage ? "![\(name)](\(path))" : "[\(name)](\(path))"
        }.joined(separator: "\n")
        apply(TextEdit(range: range, replacement: markdown,
                       selection: NSRange(location: range.location + markdown.utf16Length, length: 0)),
              actionName: "Insert Link")
    }
}

/// Draws what NSTextView does with temporary attributes on the Mac: the
/// current-line highlight, focus-mode dimming and problem underlines.
nonisolated final class EditorLayoutManager: NSLayoutManager {
    /// The highlighted line, in text-container coordinates.
    var currentLineRect: CGRect?
    /// Characters outside this range are dimmed (focus mode).
    var focusRange: NSRange?
    var problems: [DocumentProblem] = []

    private var isDimming = false

    static let currentLineColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.045) : UIColor.black.withAlphaComponent(0.035)
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        if let line = currentLineRect, let context = UIGraphicsGetCurrentContext(), let container = textContainers.first {
            context.setFillColor(Self.currentLineColor.cgColor)
            // Edge to edge, including the text container's insets.
            context.fill(CGRect(x: 0, y: line.minY + origin.y, width: container.size.width + origin.x * 2, height: line.height))
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        if let focus = focusRange {
            let focusGlyphs = glyphRange(forCharacterRange: focus, actualCharacterRange: nil)
            let before = NSRange(location: glyphsToShow.location, length: max(0, min(NSMaxRange(glyphsToShow), focusGlyphs.location) - glyphsToShow.location))
            let inside = NSIntersectionRange(glyphsToShow, focusGlyphs)
            let afterStart = max(glyphsToShow.location, NSMaxRange(focusGlyphs))
            let after = NSRange(location: afterStart, length: max(0, NSMaxRange(glyphsToShow) - afterStart))
            for (range, dim) in [(before, true), (inside, false), (after, true)] where range.length > 0 {
                isDimming = dim
                super.drawGlyphs(forGlyphRange: range, at: origin)
            }
            isDimming = false
        } else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        }
        drawProblemUnderlines(in: glyphsToShow, at: origin)
    }

    override func showCGGlyphs(_ glyphs: UnsafePointer<CGGlyph>, positions: UnsafePointer<CGPoint>, count glyphCount: Int,
                               font: UIFont, textMatrix: CGAffineTransform, attributes: [NSAttributedString.Key: Any] = [:],
                               in context: CGContext) {
        guard isDimming else {
            return super.showCGGlyphs(glyphs, positions: positions, count: glyphCount, font: font,
                                      textMatrix: textMatrix, attributes: attributes, in: context)
        }
        context.saveGState()
        context.setAlpha(0.3)
        super.showCGGlyphs(glyphs, positions: positions, count: glyphCount, font: font,
                           textMatrix: textMatrix, attributes: attributes, in: context)
        context.restoreGState()
    }

    /// Warnings get thick orange dots, notes thin blue dashes, so they differ in more than color.
    private func drawProblemUnderlines(in glyphsToShow: NSRange, at origin: CGPoint) {
        guard !problems.isEmpty, let container = textContainers.first, let storage = textStorage else { return }
        let shown = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        for problem in problems {
            let range = NSIntersectionRange(NSIntersectionRange(problem.range, shown), NSRange(location: 0, length: storage.length))
            guard range.length > 0 else { continue }
            let isWarning = problem.severity == .warning
            let color = isWarning ? UIColor.systemOrange : UIColor.systemBlue
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                    in: container) { rect, _ in
                let y = rect.maxY + origin.y - (isWarning ? 1.5 : 1)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: rect.minX + origin.x, y: y))
                path.addLine(to: CGPoint(x: rect.maxX + origin.x, y: y))
                path.lineWidth = isWarning ? 2 : 1
                path.lineCapStyle = isWarning ? .round : .butt
                path.setLineDash(isWarning ? [0.01, 4] : [3, 2], count: 2, phase: 0)
                color.setStroke()
                path.stroke()
            }
        }
    }
}
#endif
