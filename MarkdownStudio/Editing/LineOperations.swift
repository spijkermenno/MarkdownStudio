import Foundation

/// Moving, duplicating and renumbering whole lines.
nonisolated extension MarkdownEditing {
    private static let listItem = try! NSRegularExpression(pattern: "^([ \\t]*)(?:[-*+]|\\d{1,9}[.)])(?:[ \\t]+|$)")
    private static let orderedItem = try! NSRegularExpression(pattern: "^([ \\t]*)(\\d{1,9})([.)])(?:[ \\t]+|$)")

    // MARK: - Move & duplicate

    /// Moves the selected lines one line (or one sibling list item) up or down.
    /// A single list item moves together with its nested lines.
    static func moveLines(_ text: String, selection: NSRange, up: Bool) -> TextEdit? {
        var lines = text.components(separatedBy: "\n")
        // The empty "line" after a final newline is not something to swap with.
        let count = lines.count > 1 && lines.last == "" ? lines.count - 1 : lines.count
        var (first, last) = selectedLineIndices(text, selection)
        guard first < count else { return nil }
        if first == last { last = itemEnd(lines, first, limit: count) }
        last = min(last, count - 1)
        let block = Array(lines[first...last])

        let regionStart: Int
        let regionEnd: Int
        let shift: Int
        if up {
            guard first > 0 else { return nil }
            var previous = first - 1
            if let indent = listIndent(lines[first]) {
                var p = first - 1
                while p >= 0, !isBlank(lines[p]), indentWidth(lines[p]) > indent { p -= 1 }
                if p >= 0, listIndent(lines[p]) == indent { previous = p }
            }
            let moved = Array(lines[previous..<first])
            lines.replaceSubrange(previous...last, with: block + moved)
            regionStart = previous
            regionEnd = last
            shift = -(moved.joined(separator: "\n").utf16Length + 1)
        } else {
            guard last + 1 < count else { return nil }
            let nextStart = last + 1
            var nextEnd = nextStart
            if let indent = listIndent(lines[first]), listIndent(lines[nextStart]) == indent {
                nextEnd = itemEnd(lines, nextStart, limit: count)
            }
            let moved = Array(lines[nextStart...nextEnd])
            lines.replaceSubrange(first...nextEnd, with: moved + block)
            regionStart = first
            regionEnd = nextEnd
            shift = moved.joined(separator: "\n").utf16Length + 1
        }

        let original = text.components(separatedBy: "\n")
        let start = offset(ofLine: regionStart, in: original)
        let end = offset(ofLine: regionEnd, in: original) + original[regionEnd].utf16Length
        let replacement = lines[regionStart...regionEnd].joined(separator: "\n")
        return TextEdit(range: NSRange(location: start, length: end - start), replacement: replacement,
                        selection: NSRange(location: selection.location + shift, length: selection.length))
    }

    /// Duplicates the selected lines below themselves and selects the copy.
    static func duplicateLines(_ text: String, selection: NSRange) -> TextEdit {
        let lines = text.components(separatedBy: "\n")
        let (first, last) = selectedLineIndices(text, selection)
        let block = lines[first...last].joined(separator: "\n")
        let end = offset(ofLine: last, in: lines) + lines[last].utf16Length
        let shift = block.utf16Length + 1
        return TextEdit(range: NSRange(location: end, length: 0), replacement: "\n" + block,
                        selection: NSRange(location: selection.location + shift, length: selection.length))
    }

    // MARK: - Renumbering

    /// Renumbers the ordered list that contains `line` (zero-based), keeping the
    /// first item's number. Only the list level of that line is changed.
    /// Returns nil when the numbers are already sequential.
    static func renumberList(_ text: String, line: Int, selection: NSRange? = nil) -> TextEdit? {
        let lines = text.components(separatedBy: "\n")
        guard line >= 0, line < lines.count else { return nil }

        // The ordered item this line belongs to.
        var anchor = line
        while anchor >= 0, orderedMatch(lines[anchor]) == nil { anchor -= 1 }
        guard anchor >= 0, let anchorIndent = listIndent(lines[anchor]) else { return nil }
        if anchor < line {
            for i in (anchor + 1)...line where !isBlank(lines[i]) && indentWidth(lines[i]) <= anchorIndent {
                return nil
            }
        }

        func belongs(_ i: Int) -> Bool? {
            let l = lines[i]
            if isBlank(l) { return true }
            if indentWidth(l) > anchorIndent { return true }
            if indentWidth(l) == anchorIndent, orderedMatch(l) != nil { return true }
            return nil
        }
        var start = anchor
        var i = anchor - 1
        while i >= 0, belongs(i) == true {
            if orderedMatch(lines[i]) != nil, indentWidth(lines[i]) == anchorIndent { start = i }
            i -= 1
        }
        var end = anchor
        i = anchor + 1
        while i < lines.count, belongs(i) == true {
            if orderedMatch(lines[i]) != nil, indentWidth(lines[i]) == anchorIndent { end = i }
            i += 1
        }

        var newLines = Array(lines[start...end])
        var number = Int(orderedMatch(lines[start])!.number) ?? 1
        var deltas: [Int: Int] = [:]
        for index in start...end {
            let l = lines[index]
            guard indentWidth(l) == anchorIndent, let match = orderedMatch(l) else { continue }
            let replacement = String(number)
            if match.number != replacement {
                let updated = (l as NSString).replacingCharacters(in: match.numberRange, with: replacement)
                newLines[index - start] = updated
                deltas[index] = updated.utf16Length - l.utf16Length
            }
            number += 1
        }
        guard !deltas.isEmpty else { return nil }

        let rangeStart = offset(ofLine: start, in: lines)
        let rangeEnd = offset(ofLine: end, in: lines) + lines[end].utf16Length
        var newSelection = selection ?? NSRange(location: rangeStart, length: 0)
        if let selection {
            let caretLine = lineIndex(of: selection.location, in: lines)
            var shift = 0
            for (index, delta) in deltas where index < caretLine { shift += delta }
            if let delta = deltas[caretLine], selection.location - offset(ofLine: caretLine, in: lines) > anchorIndent {
                shift += delta
            }
            newSelection = NSRange(location: selection.location + shift, length: selection.length)
        }
        return TextEdit(range: NSRange(location: rangeStart, length: rangeEnd - rangeStart),
                        replacement: newLines.joined(separator: "\n"), selection: newSelection)
    }

    // MARK: - Helpers

    static func isBlank(_ line: String) -> Bool {
        line.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\r" }
    }

    static func indentWidth(_ line: String) -> Int {
        var width = 0
        for ch in line {
            if ch == " " { width += 1 } else if ch == "\t" { width += 4 } else { break }
        }
        return width
    }

    /// Indentation of a list item line, or nil when the line isn't a list item.
    static func listIndent(_ line: String) -> Int? {
        listItem.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16Length)) == nil ? nil : indentWidth(line)
    }

    private static func orderedMatch(_ line: String) -> (number: String, numberRange: NSRange)? {
        guard let m = orderedItem.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16Length)) else { return nil }
        return ((line as NSString).substring(with: m.range(at: 2)), m.range(at: 2))
    }

    /// The last line belonging to the list item at `index` (its nested and continuation lines).
    static func itemEnd(_ lines: [String], _ index: Int, limit: Int) -> Int {
        guard let indent = listIndent(lines[index]) else { return index }
        var end = index
        var i = index + 1
        while i < limit {
            if isBlank(lines[i]) {
                var j = i
                while j < limit, isBlank(lines[j]) { j += 1 }
                guard j < limit, indentWidth(lines[j]) > indent else { break }
                i = j
                continue
            }
            guard indentWidth(lines[i]) > indent else { break }
            end = i
            i += 1
        }
        return end
    }

    private static func selectedLineIndices(_ text: String, _ selection: NSRange) -> (Int, Int) {
        let index = LineIndex(text)
        let first = index.line(containing: selection.location)
        let lastOffset = selection.length > 0 ? NSMaxRange(selection) - 1 : selection.location
        return (first, max(first, index.line(containing: lastOffset)))
    }

    private static func offset(ofLine line: Int, in lines: [String]) -> Int {
        lines[..<line].reduce(0) { $0 + $1.utf16Length + 1 }
    }

    private static func lineIndex(of location: Int, in lines: [String]) -> Int {
        var offset = 0
        for (i, line) in lines.enumerated() {
            let next = offset + line.utf16Length + 1
            if location < next { return i }
            offset = next
        }
        return max(0, lines.count - 1)
    }
}
