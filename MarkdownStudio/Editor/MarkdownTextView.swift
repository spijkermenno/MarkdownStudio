import AppKit
import UniformTypeIdentifiers

/// The editor's text view: smart lists, auto-pairing, Markdown-aware paste
/// and drop, current-line highlight.
final class MarkdownTextView: NSTextView {
    var autoPairing = true
    var smartLists = true
    var highlightCurrentLine = true {
        didSet { needsDisplay = true }
    }

    /// The document's folder, used to make dropped and pasted files relative.
    var documentURL: URL?

    static let currentLineColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.045)
            : NSColor.black.withAlphaComponent(0.035)
    }

    private static let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "`": "`"]
    private static let wrapOnly: Set<String> = ["*", "_", "~", "=", "\"", "<"]
    private static let closers: Set<String> = [")", "]", "}", "`"]

    // MARK: - Editing helpers

    /// Performs an edit through the text system so it is undoable.
    func apply(_ edit: TextEdit, actionName: String? = nil) {
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        if let actionName { undoManager?.setActionName(actionName) }
        let length = (string as NSString).length
        let selection = NSRange(location: min(edit.selection.location, length),
                                length: min(edit.selection.length, max(0, length - edit.selection.location)))
        setSelectedRange(selection)
        scrollRangeToVisible(selection)
    }

    // MARK: - Smart typing

    override func insertNewline(_ sender: Any?) {
        if smartLists, let edit = MarkdownEditing.newline(string, selection: selectedRange()) {
            apply(edit)
            return
        }
        super.insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
        let selection = selectedRange()
        let multiline = (string as NSString).substring(with: selection).contains("\n")
        if smartLists && (multiline || MarkdownEditing.isListLine(string, at: selection.location)) {
            apply(MarkdownEditing.indent(string, selection: selection), actionName: "Indent")
            return
        }
        insertText(MarkdownEditing.indentUnit, replacementRange: selection)
    }

    override func insertBacktab(_ sender: Any?) {
        apply(MarkdownEditing.outdent(string, selection: selectedRange()), actionName: "Outdent")
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard autoPairing, !hasMarkedText(), replacementRange.location == NSNotFound,
              let typed = insertString as? String, typed.utf16.count == 1
        else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        let ns = string as NSString
        let selection = selectedRange()
        let next = selection.location < ns.length ? ns.substring(with: NSRange(location: selection.location, length: 1)) : ""
        let previous = selection.location > 0 ? ns.substring(with: NSRange(location: selection.location - 1, length: 1)) : ""

        // Wrap a selection: typing * around "word" gives *word*.
        if selection.length > 0, let close = Self.pairs[typed] ?? (Self.wrapOnly.contains(typed) ? (typed == "<" ? ">" : typed) : nil) {
            let selected = ns.substring(with: selection)
            apply(TextEdit(range: selection, replacement: typed + selected + close,
                           selection: NSRange(location: selection.location + 1, length: selection.length)))
            return
        }

        // Step over an auto-inserted closing character.
        if selection.length == 0, Self.closers.contains(typed), next == typed {
            setSelectedRange(NSRange(location: selection.location + 1, length: 0))
            return
        }

        // Insert a pair when the caret is not directly before a word.
        if selection.length == 0, let close = Self.pairs[typed] {
            let nextIsFree = next.isEmpty || next.rangeOfCharacter(from: .whitespacesAndNewlines) != nil || Self.closers.contains(next)
            // A backtick after another backtick (fence) or a word (closing a span) is typed as-is.
            let closesBacktick = typed == "`" && (previous == "`" || previous.rangeOfCharacter(from: .alphanumerics) != nil)
            if nextIsFree && !closesBacktick {
                apply(TextEdit(range: selection, replacement: typed + close,
                               selection: NSRange(location: selection.location + 1, length: 0)))
                return
            }
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        let ns = string as NSString
        if autoPairing, selection.length == 0, selection.location > 0, selection.location < ns.length {
            let previous = ns.substring(with: NSRange(location: selection.location - 1, length: 1))
            let next = ns.substring(with: NSRange(location: selection.location, length: 1))
            if let close = Self.pairs[previous], close == next {
                apply(TextEdit(range: NSRange(location: selection.location - 1, length: 2), replacement: "",
                               selection: NSRange(location: selection.location - 1, length: 0)))
                return
            }
        }
        super.deleteBackward(sender)
    }

    // MARK: - Paste and drop

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let selection = selectedRange()

        // Pasting a URL over selected text creates a link.
        if selection.length > 0, let pasted = pasteboard.string(forType: .string), MarkdownEditing.looksLikeURL(pasted) {
            let selected = (string as NSString).substring(with: selection)
            if !MarkdownEditing.looksLikeURL(selected) {
                apply(MarkdownEditing.insertLink(string, selection: selection, clipboardURL: pasted), actionName: "Paste Link")
                return
            }
        }

        // Pasting image data saves it next to the document.
        if pasteboard.string(forType: .string) == nil,
           pasteboard.availableType(from: [.fileURL]) == nil,
           let image = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            pasteImage(image)
            return
        }

        if let urls = fileURLs(from: pasteboard), !urls.isEmpty {
            insertLinks(to: urls, at: selection)
            return
        }
        super.paste(sender)
    }

    private func pasteImage(_ data: Data) {
        guard let documentURL else {
            let alert = NSAlert()
            alert.messageText = "Save the document first"
            alert.informativeText = "Pasted images are saved in an “assets” folder next to the document, so it needs a location on disk."
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return
        }
        let png: Data
        if let rep = NSBitmapImageRep(data: data), let converted = rep.representation(using: .png, properties: [:]) {
            png = converted
        } else {
            png = data
        }
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
            insertLinks(to: [file], at: selectedRange())
        } catch {
            presentError(error)
        }
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if let urls = fileURLs(from: sender.draggingPasteboard), !urls.isEmpty {
            let point = convert(sender.draggingLocation, from: nil)
            let index = characterIndexForInsertion(at: point)
            insertLinks(to: urls, at: NSRange(location: index, length: 0))
            window?.makeFirstResponder(self)
            return true
        }
        return super.performDragOperation(sender)
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
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

    // MARK: - Current line highlight

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard highlightCurrentLine, selectedRange().length == 0,
              let layoutManager, let textContainer, window?.firstResponder === self else { return }
        let ns = string as NSString
        let location = selectedRange().location
        let lineRect: NSRect
        if location >= ns.length, ns.length == 0 || ns.character(at: ns.length - 1) == 0x0A {
            lineRect = layoutManager.extraLineFragmentRect
        } else {
            let line = ns.lineContentRange(at: min(location, ns.length))
            let glyphs = layoutManager.glyphRange(forCharacterRange: line, actualCharacterRange: nil)
            var bounds = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            if glyphs.length == 0 {
                bounds = layoutManager.lineFragmentRect(forGlyphAt: min(glyphs.location, max(0, layoutManager.numberOfGlyphs - 1)), effectiveRange: nil)
            }
            lineRect = bounds
        }
        guard !lineRect.isEmpty else { return }
        let highlight = NSRect(x: 0, y: lineRect.minY + textContainerOrigin.y, width: bounds.width, height: lineRect.height)
        Self.currentLineColor.setFill()
        highlight.intersection(rect).fill()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if highlightCurrentLine { needsDisplay = true }
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }
}

enum MarkdownPaths {
    /// A Markdown-ready (percent-encoded) path to `url`, relative to `directory` when possible.
    nonisolated static func relativePath(to url: URL, from directory: URL?) -> String {
        guard let directory else { return url.absoluteString }
        let target = url.standardizedFileURL.pathComponents
        let base = directory.standardizedFileURL.pathComponents
        var common = 0
        while common < min(target.count, base.count), target[common] == base[common] { common += 1 }
        // Only the root in common: an absolute path is clearer.
        guard common > 1 else { return url.absoluteString }
        let ups = Array(repeating: "..", count: base.count - common)
        let path = (ups + target[common...]).joined(separator: "/")
        return path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    }
}
