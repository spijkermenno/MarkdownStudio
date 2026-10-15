import Foundation

/// A linked table of contents between `<!-- toc -->` and `<!-- /toc -->`.
/// The markers are HTML comments, so other Markdown tools ignore them.
nonisolated enum TableOfContents {
    static let startMarker = "<!-- toc -->"
    static let endMarker = "<!-- /toc -->"

    /// The nested list of links for headings after `afterLine`.
    static func list(for text: String, afterLine: Int) -> String {
        let items = OutlineParser.parse(text).filter { $0.line > afterLine }
        var stack: [Int] = []
        return items.map { item in
            // Depth = number of open ancestor levels, so skipped levels still nest correctly.
            while let last = stack.last, last >= item.level { stack.removeLast() }
            let depth = stack.count
            stack.append(item.level)
            let title = item.title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            return String(repeating: "  ", count: depth) + "- [\(title)](#\(item.anchor))"
        }.joined(separator: "\n")
    }

    /// Line numbers of the existing markers, if the document has a TOC.
    static func markers(in text: String) -> (start: Int, end: Int)? {
        let lines = text.components(separatedBy: "\n")
        // Markers shown inside a code block (e.g. documentation of this feature) don't count.
        let index = LineIndex(text)
        let code = MarkdownHighlighter.fencedCodeRanges(in: text)
        func isMarker(_ i: Int, _ marker: String) -> Bool {
            guard lines[i].trimmingCharacters(in: .whitespaces) == marker else { return false }
            let offset = index.start(ofLine: i)
            return !code.contains { NSLocationInRange(offset, $0) }
        }
        guard let start = lines.indices.first(where: { isMarker($0, startMarker) }),
              let end = lines.indices.first(where: { $0 > start && isMarker($0, endMarker) })
        else { return nil }
        return (start, end)
    }

    /// Brings an existing TOC up to date; nil when there is none or it's current.
    static func update(_ text: String) -> TextEdit? {
        guard text.contains(startMarker), let markers = markers(in: text) else { return nil }
        let index = LineIndex(text)
        let contentStart = index.start(ofLine: markers.start + 1)
        let contentEnd = index.start(ofLine: markers.end)
        let current = (text as NSString).substring(with: NSRange(location: contentStart, length: contentEnd - contentStart))
        let list = list(for: text, afterLine: markers.end)
        let wanted = list.isEmpty ? "" : list + "\n"
        guard current != wanted else { return nil }
        return TextEdit(range: NSRange(location: contentStart, length: contentEnd - contentStart), replacement: wanted,
                        selection: NSRange(location: contentStart, length: 0))
    }

    /// Inserts a TOC at the caret, or refreshes the existing one.
    static func insert(_ text: String, selection: NSRange) -> TextEdit? {
        if markers(in: text) != nil { return update(text) }
        let caretLine = LineIndex(text).line(containing: selection.location)
        let list = list(for: text, afterLine: caretLine)
        let body = list.isEmpty ? "" : list + "\n"
        return MarkdownEditing.insertBlock("\(startMarker)\n\(body)\(endMarker)", in: text, selection: selection, caretOffset: nil)
    }
}
