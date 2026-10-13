import Foundation

/// Re-aligns the pipes of the Markdown table around the caret.
nonisolated enum TableFormatter {
    enum Alignment: Sendable { case none, left, center, right }

    private static let delimiterRow = try! NSRegularExpression(
        pattern: "^[ \\t]*\\|?[ \\t]*:?-+:?[ \\t]*(\\|[ \\t]*:?-+:?[ \\t]*)*\\|?[ \\t]*$")

    static func formatTable(_ text: String, at location: Int) -> TextEdit? {
        let ns = text as NSString
        let index = LineIndex(text)
        let caretLine = index.line(containing: location)

        func content(_ line: Int) -> String {
            ns.substring(with: ns.lineContentRange(at: index.start(ofLine: line)))
        }
        func isTableLine(_ line: Int) -> Bool {
            line >= 0 && line < index.lineCount && content(line).contains("|")
        }
        guard isTableLine(caretLine) else { return nil }

        var first = caretLine
        var last = caretLine
        while isTableLine(first - 1) { first -= 1 }
        while isTableLine(last + 1) { last += 1 }
        let lines = (first...last).map(content)
        guard lines.count >= 2,
              delimiterRow.firstMatch(in: lines[1], range: NSRange(location: 0, length: lines[1].utf16Length)) != nil
        else { return nil }

        let rows = lines.map(splitRow)
        let alignments = rows[1].map(alignment)
        let columns = rows.map(\.count).max() ?? 0
        var widths = Array(repeating: 3, count: columns)
        for (i, row) in rows.enumerated() where i != 1 {
            for (c, cell) in row.enumerated() { widths[c] = max(widths[c], cell.count) }
        }

        let formatted = rows.enumerated().map { i, row -> String in
            let cells = (0..<columns).map { c -> String in
                let align = c < alignments.count ? alignments[c] : .none
                if i == 1 { return delimiter(width: widths[c], alignment: align) }
                return pad(c < row.count ? row[c] : "", width: widths[c], alignment: align)
            }
            return "| " + cells.joined(separator: " | ") + " |"
        }.joined(separator: "\n")

        let start = index.start(ofLine: first)
        let end = NSMaxRange(ns.lineContentRange(at: index.start(ofLine: last)))
        let range = NSRange(location: start, length: end - start)
        // Put the caret at the start of the first cell of the same row.
        let rowOffset = formatted.components(separatedBy: "\n").prefix(caretLine - first).reduce(0) { $0 + $1.utf16Length + 1 }
        return TextEdit(range: range, replacement: formatted,
                        selection: NSRange(location: start + rowOffset + 2, length: 0))
    }

    /// Splits a row on unescaped pipes outside code spans.
    static func splitRow(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var inCode = false
        var escaped = false
        for ch in line.trimmingCharacters(in: .whitespaces) {
            if escaped { current.append(ch); escaped = false; continue }
            switch ch {
            case "\\": current.append(ch); escaped = true
            case "`": current.append(ch); inCode.toggle()
            case "|" where !inCode:
                cells.append(current)
                current = ""
            default: current.append(ch)
            }
        }
        cells.append(current)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|"), !cells.isEmpty { cells.removeFirst() }
        if trimmed.hasSuffix("|") && !trimmed.hasSuffix("\\|"), !cells.isEmpty { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func alignment(_ cell: String) -> Alignment {
        let left = cell.hasPrefix(":"), right = cell.hasSuffix(":")
        switch (left, right) {
        case (true, true): return .center
        case (true, false): return .left
        case (false, true): return .right
        default: return .none
        }
    }

    private static func delimiter(width: Int, alignment: Alignment) -> String {
        switch alignment {
        case .none: return String(repeating: "-", count: width)
        case .left: return ":" + String(repeating: "-", count: width - 1)
        case .right: return String(repeating: "-", count: width - 1) + ":"
        case .center: return ":" + String(repeating: "-", count: width - 2) + ":"
        }
    }

    private static func pad(_ cell: String, width: Int, alignment: Alignment) -> String {
        let space = width - cell.count
        switch alignment {
        case .right: return String(repeating: " ", count: space) + cell
        case .center:
            let left = space / 2
            return String(repeating: " ", count: left) + cell + String(repeating: " ", count: space - left)
        default: return cell + String(repeating: " ", count: space)
        }
    }
}
