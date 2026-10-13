import Foundation

/// Pure text transformations behind the editor's formatting commands and
/// smart typing. Each function takes the full text and the current selection
/// and returns the edit to perform (or `nil` when it doesn't apply).
nonisolated enum MarkdownEditing {
    static let indentUnit = "    "

    // MARK: - Inline wrapping (bold, italic, code, …)

    /// Toggles `marker` around the selection. With an empty selection the word
    /// under the caret is used; outside a word an empty pair is inserted.
    static func toggleWrap(_ text: String, selection: NSRange, marker: String) -> TextEdit {
        let ns = text as NSString
        var range = selection
        if range.length == 0 {
            let word = wordRange(in: ns, at: range.location)
            if word.length > 0 { range = word }
        }
        let m = (marker as NSString).length
        let selected = ns.substring(with: range)

        // Markers just outside the selection: **|bold|**
        let leftRun = run(of: marker, in: ns, endingAt: range.location)
        let rightRun = run(of: marker, in: ns, startingAt: NSMaxRange(range))
        if range.length > 0, isWrapped(leftRun: leftRun, rightRun: rightRun, marker: marker) {
            let outer = NSRange(location: range.location - m, length: range.length + 2 * m)
            return TextEdit(range: outer, replacement: selected,
                            selection: NSRange(location: outer.location, length: range.length))
        }

        // Markers inside the selection: |**bold**|
        let innerLeft = run(of: marker, in: selected as NSString, startingAt: 0)
        let innerRight = run(of: marker, in: selected as NSString, endingAt: (selected as NSString).length)
        if range.length >= 2 * m, isWrapped(leftRun: innerLeft, rightRun: innerRight, marker: marker) {
            let inner = (selected as NSString).substring(with: NSRange(location: m, length: range.length - 2 * m))
            return TextEdit(range: range, replacement: inner,
                            selection: NSRange(location: range.location, length: inner.utf16Length))
        }

        if range.length == 0 {
            return TextEdit(range: range, replacement: marker + marker,
                            selection: NSRange(location: range.location + m, length: 0))
        }
        return TextEdit(range: range, replacement: marker + selected + marker,
                        selection: NSRange(location: range.location + m, length: range.length))
    }

    /// `*` needs care so italic doesn't unwrap bold: a run of 2 is bold, 1 or 3 contains italic.
    private static func isWrapped(leftRun: Int, rightRun: Int, marker: String) -> Bool {
        let m = marker.count
        guard leftRun >= m, rightRun >= m else { return false }
        if marker.count == 1, marker == "*" || marker == "_" {
            return leftRun % 2 == 1 && rightRun % 2 == 1
        }
        return true
    }

    /// Number of consecutive marker characters (markers are runs of one character: `*`, `**`, `~~`, …).
    private static func run(of marker: String, in ns: NSString, endingAt end: Int) -> Int {
        guard let unit = marker.utf16.first else { return 0 }
        var count = 0
        var i = end - 1
        while i >= 0, ns.character(at: i) == unit { count += 1; i -= 1 }
        return count
    }

    private static func run(of marker: String, in ns: NSString, startingAt start: Int) -> Int {
        guard let unit = marker.utf16.first else { return 0 }
        var count = 0
        var i = start
        while i < ns.length, ns.character(at: i) == unit { count += 1; i += 1 }
        return count
    }

    static func wordRange(in ns: NSString, at location: Int) -> NSRange {
        let wordChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'-"))
        func isWord(_ i: Int) -> Bool {
            guard i >= 0, i < ns.length, let scalar = Unicode.Scalar(ns.character(at: i)) else { return false }
            return wordChars.contains(scalar)
        }
        var start = location
        var end = location
        while isWord(start - 1) { start -= 1 }
        while isWord(end) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    // MARK: - Links and images

    static func insertLink(_ text: String, selection: NSRange, image: Bool = false, clipboardURL: String? = nil) -> TextEdit {
        let ns = text as NSString
        let selected = ns.substring(with: selection)
        let prefix = image ? "![" : "["
        let p = prefix.utf16Length

        if looksLikeURL(selected) {
            let replacement = "\(prefix)](\(selected))"
            return TextEdit(range: selection, replacement: replacement,
                            selection: NSRange(location: selection.location + p, length: 0))
        }
        let url = clipboardURL.flatMap { looksLikeURL($0) ? $0.trimmingCharacters(in: .whitespacesAndNewlines) : nil }
        let replacement = "\(prefix)\(selected)](\(url ?? ""))"
        let caret: Int
        if selected.isEmpty {
            caret = selection.location + p                                  // type the link text
        } else if url != nil {
            caret = selection.location + replacement.utf16Length            // done
        } else {
            caret = selection.location + replacement.utf16Length - 1        // inside the empty ()
        }
        return TextEdit(range: selection, replacement: replacement, selection: NSRange(location: caret, length: 0))
    }

    static func looksLikeURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.contains("\n") else { return false }
        let lower = trimmed.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:") || lower.hasPrefix("ftp://")
    }

    // MARK: - Line prefixes (headings, quotes, lists)

    private static let headingPrefix = try! NSRegularExpression(pattern: "^#{1,6}[ \\t]+|^#{1,6}$")
    private static let listPrefix = try! NSRegularExpression(pattern: "^([ \\t]*)(?:[-*+]|\\d+[.)])[ \\t]+(?:\\[[ xX]\\][ \\t]+)?")
    private static let quotePrefix = try! NSRegularExpression(pattern: "^[ \\t]*>[ \\t]?")

    /// Sets the heading level (0 = paragraph) on every selected line.
    static func setHeading(_ text: String, selection: NSRange, level: Int) -> TextEdit {
        transformLines(text, selection: selection) { line, _ in
            let stripped = replacingFirstMatch(headingPrefix, in: line, with: "")
            return level == 0 ? stripped : String(repeating: "#", count: level) + " " + stripped
        }
    }

    /// Cycles the heading level of the caret's line: none → H1 → … → H6 → none.
    static func cycleHeading(_ text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let line = ns.substring(with: ns.lineContentRange(at: selection.location))
        let current = headingLevel(of: line)
        return setHeading(text, selection: selection, level: current >= 6 ? 0 : current + 1)
    }

    static func headingLevel(of line: String) -> Int {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return 0 }
        let rest = line.dropFirst(hashes)
        return rest.isEmpty || rest.first == " " || rest.first == "\t" ? hashes : 0
    }

    static func toggleBlockquote(_ text: String, selection: NSRange) -> TextEdit {
        let lines = selectedLines(text, selection: selection)
        let allQuoted = lines.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty || matches(quotePrefix, $0) }
        return transformLines(text, selection: selection) { line, _ in
            if allQuoted { return replacingFirstMatch(quotePrefix, in: line, with: "") }
            return line.isEmpty ? ">" : "> " + line
        }
    }

    enum ListKind: Sendable { case bullet, numbered, task }

    static func toggleList(_ text: String, selection: NSRange, kind: ListKind) -> TextEdit {
        let lines = selectedLines(text, selection: selection)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let alreadyKind = !nonEmpty.isEmpty && nonEmpty.allSatisfy { listKind(of: $0) == kind }
        var number = 0
        return transformLines(text, selection: selection) { line, _ in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            let match = listPrefix.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16Length))
            let indent = match.map { (line as NSString).substring(with: $0.range(at: 1)) } ?? String(line.prefix { $0 == " " || $0 == "\t" })
            let body = match.map { (line as NSString).substring(from: NSMaxRange($0.range)) } ?? String(line.dropFirst(indent.count))
            if alreadyKind { return indent + body }
            number += 1
            switch kind {
            case .bullet: return indent + "- " + body
            case .numbered: return indent + "\(number). " + body
            case .task: return indent + "- [ ] " + body
            }
        }
    }

    static func listKind(of line: String) -> ListKind? {
        guard let match = listPrefix.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16Length)) else { return nil }
        let prefix = (line as NSString).substring(with: match.range)
        if prefix.contains("[") { return .task }
        return prefix.trimmingCharacters(in: .whitespaces).first?.isNumber == true ? .numbered : .bullet
    }

    // MARK: - Blocks

    static func toggleCodeBlock(_ text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let lines = ns.lineRanges(touching: selection)
        let first = lines.first!, last = lines.last!
        let block = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        let content = ns.substring(with: block)

        if content.hasPrefix("```"), content.hasSuffix("```"), content.contains("\n") {
            var inner = content.components(separatedBy: "\n")
            inner.removeFirst()
            inner.removeLast()
            let replacement = inner.joined(separator: "\n")
            return TextEdit(range: block, replacement: replacement,
                            selection: NSRange(location: block.location, length: replacement.utf16Length))
        }
        if selection.length == 0 && content.trimmingCharacters(in: .whitespaces).isEmpty {
            return TextEdit(range: block, replacement: "```\n\n```",
                            selection: NSRange(location: block.location + 3, length: 0))
        }
        let replacement = "```\n" + content + "\n```"
        return TextEdit(range: block, replacement: replacement,
                        selection: NSRange(location: block.location + 3, length: 0))
    }

    static func insertHorizontalRule(_ text: String, selection: NSRange) -> TextEdit {
        insertBlock("---", in: text, selection: selection, caretOffset: nil)
    }

    static func insertTable(_ text: String, selection: NSRange) -> TextEdit {
        let table = """
        | Column 1 | Column 2 | Column 3 |
        | -------- | -------- | -------- |
        | Text     | Text     | Text     |
        """
        var edit = insertBlock(table, in: text, selection: selection, caretOffset: 2)
        edit.selection.length = "Column 1".utf16Length
        return edit
    }

    /// Inserts a block on its own lines, separated from surrounding text by blank lines.
    private static func insertBlock(_ block: String, in text: String, selection: NSRange, caretOffset: Int?) -> TextEdit {
        let ns = text as NSString
        let before = ns.substring(to: selection.location)
        let after = ns.substring(from: NSMaxRange(selection))
        var prefix = ""
        if !before.isEmpty {
            prefix = before.hasSuffix("\n\n") ? "" : (before.hasSuffix("\n") ? "\n" : "\n\n")
        }
        let suffix = after.hasPrefix("\n\n") ? "" : (after.hasPrefix("\n") ? "\n" : "\n\n")
        let replacement = prefix + block + suffix
        let caret = selection.location + prefix.utf16Length + (caretOffset ?? (block.utf16Length + min(suffix.utf16Length, 2)))
        return TextEdit(range: selection, replacement: replacement,
                        selection: NSRange(location: min(caret, selection.location + replacement.utf16Length), length: 0))
    }

    // MARK: - Indentation

    static func indent(_ text: String, selection: NSRange) -> TextEdit {
        transformLines(text, selection: selection, adjustSelection: true) { line, _ in
            line.isEmpty ? line : indentUnit + line
        }
    }

    static func outdent(_ text: String, selection: NSRange) -> TextEdit {
        transformLines(text, selection: selection, adjustSelection: true) { line, _ in
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            let spaces = line.prefix(while: { $0 == " " }).count
            return String(line.dropFirst(min(spaces, indentUnit.count)))
        }
    }

    // MARK: - Smart lists

    private static let bulletLine = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+])([ \\t]+)(\\[[ xX]\\][ \\t]+)?")
    private static let orderedLine = try! NSRegularExpression(pattern: "^([ \\t]*)(\\d{1,9})([.)])([ \\t]+)(\\[[ xX]\\][ \\t]+)?")
    private static let quoteLine = try! NSRegularExpression(pattern: "^([ \\t]*(?:>[ \\t]?)+)")

    /// Continues a list or blockquote when Return is pressed. Pressing Return on
    /// an empty item removes its marker and ends the list.
    static func newline(_ text: String, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        let lineRange = ns.lineContentRange(at: selection.location)
        let line = ns.substring(with: lineRange)
        let caretInLine = selection.location - lineRange.location
        let full = NSRange(location: 0, length: line.utf16Length)

        var marker: String?
        var continuation: String?
        if let m = bulletLine.firstMatch(in: line, range: full) {
            marker = (line as NSString).substring(with: m.range)
            let indent = (line as NSString).substring(with: m.range(at: 1))
            let bullet = (line as NSString).substring(with: m.range(at: 2))
            let space = (line as NSString).substring(with: m.range(at: 3))
            let task = m.range(at: 4).location != NSNotFound ? "[ ] " : ""
            continuation = indent + bullet + space + task
        } else if let m = orderedLine.firstMatch(in: line, range: full) {
            marker = (line as NSString).substring(with: m.range)
            let indent = (line as NSString).substring(with: m.range(at: 1))
            let number = Int((line as NSString).substring(with: m.range(at: 2))) ?? 0
            let delimiter = (line as NSString).substring(with: m.range(at: 3))
            let space = (line as NSString).substring(with: m.range(at: 4))
            let task = m.range(at: 5).location != NSNotFound ? "[ ] " : ""
            continuation = indent + "\(number + 1)" + delimiter + space + task
        } else if let m = quoteLine.firstMatch(in: line, range: full) {
            marker = (line as NSString).substring(with: m.range)
            continuation = marker!.hasSuffix(" ") ? marker : marker! + " "
        }
        guard let marker, let continuation else { return nil }
        let markerLength = marker.utf16Length
        guard caretInLine >= markerLength else { return nil }

        let content = line.dropFirst(marker.count)
        if content.trimmingCharacters(in: .whitespaces).isEmpty && caretInLine == line.utf16Length {
            // Empty item: end the list (or step out one quote level).
            return TextEdit(range: lineRange, replacement: "",
                            selection: NSRange(location: lineRange.location, length: 0))
        }
        let insertion = "\n" + continuation
        return TextEdit(range: selection, replacement: insertion,
                        selection: NSRange(location: selection.location + insertion.utf16Length, length: 0))
    }

    /// Whether the caret's line is a list item (Tab then indents the item).
    static func isListLine(_ text: String, at location: Int) -> Bool {
        let ns = text as NSString
        let line = ns.substring(with: ns.lineContentRange(at: location))
        return listKind(of: line) != nil
    }

    // MARK: - Task lists

    private static let taskBox = try! NSRegularExpression(pattern: "^([ \\t]*(?:>[ \\t]?)*[ \\t]*(?:(?:[-*+]|\\d+[.)])[ \\t]+)+\\[)([ xX])(\\])")

    /// Toggles the checkbox on a zero-based source line.
    static func toggleTask(_ text: String, line: Int) -> TextEdit? {
        let ns = text as NSString
        let index = LineIndex(text)
        guard line >= 0, line < index.lineCount else { return nil }
        let lineRange = ns.lineContentRange(at: index.start(ofLine: line))
        let content = ns.substring(with: lineRange)
        guard let match = taskBox.firstMatch(in: content, range: NSRange(location: 0, length: content.utf16Length)) else { return nil }
        let boxRange = match.range(at: 2)
        let current = (content as NSString).substring(with: boxRange)
        let absolute = NSRange(location: lineRange.location + boxRange.location, length: boxRange.length)
        return TextEdit(range: absolute, replacement: current == " " ? "x" : " ",
                        selection: NSRange(location: absolute.location, length: 0))
    }

    // MARK: - Helpers

    static func selectedLines(_ text: String, selection: NSRange) -> [String] {
        let ns = text as NSString
        return ns.lineRanges(touching: selection).map { ns.substring(with: $0) }
    }

    /// Replaces every line touched by the selection with `transform(line, index)`.
    /// The resulting selection covers the transformed lines, or follows the
    /// caret when `adjustSelection` is set and nothing was selected.
    static func transformLines(_ text: String, selection: NSRange, adjustSelection: Bool = false,
                               _ transform: (String, Int) -> String) -> TextEdit {
        let ns = text as NSString
        let ranges = ns.lineRanges(touching: selection)
        let block = NSRange(location: ranges.first!.location, length: NSMaxRange(ranges.last!) - ranges.first!.location)
        let originalLines = ranges.map { ns.substring(with: $0) }
        let newLines = originalLines.enumerated().map { transform($1, $0) }
        let replacement = newLines.joined(separator: "\n")

        if ranges.count == 1 {
            // Keep the caret at the same place relative to the end of the line.
            let delta = replacement.utf16Length - originalLines[0].utf16Length
            let fromEnd = NSMaxRange(block) - NSMaxRange(selection)
            let end = max(block.location, block.location + replacement.utf16Length - fromEnd)
            let start = selection.length == 0 ? end : max(block.location, selection.location + delta)
            return TextEdit(range: block, replacement: replacement,
                            selection: NSRange(location: min(start, end), length: max(0, end - start)))
        }
        return TextEdit(range: block, replacement: replacement,
                        selection: NSRange(location: block.location, length: replacement.utf16Length))
    }

    private static func matches(_ regex: NSRegularExpression, _ string: String) -> Bool {
        regex.firstMatch(in: string, range: NSRange(location: 0, length: string.utf16Length)) != nil
    }

    private static func replacingFirstMatch(_ regex: NSRegularExpression, in string: String, with template: String) -> String {
        guard let match = regex.firstMatch(in: string, range: NSRange(location: 0, length: string.utf16Length)) else { return string }
        return (string as NSString).replacingCharacters(in: match.range, with: template)
    }
}
