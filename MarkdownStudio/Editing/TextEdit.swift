import Foundation

/// A single replacement in the editor's text, plus the selection to apply
/// afterwards. All ranges are UTF-16 based so they map directly onto
/// `NSTextView` / `NSString`.
nonisolated struct TextEdit: Equatable, Sendable {
    var range: NSRange
    var replacement: String
    var selection: NSRange

    /// Applies the edit to a string. Used by tests and for edits made while
    /// no text view is attached.
    func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

nonisolated extension NSString {
    /// The ranges of every line touched by `range`, without line terminators.
    func lineRanges(touching range: NSRange) -> [NSRange] {
        var result: [NSRange] = []
        let covering = lineRange(for: range)
        var location = covering.location
        repeat {
            var start = 0, end = 0, contentsEnd = 0
            getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            result.append(NSRange(location: start, length: contentsEnd - start))
            if end == location { break }
            location = end
        } while location < NSMaxRange(covering)
        // A selection that ends exactly at the start of a line shouldn't pull that line in.
        if result.count > 1, range.length > 0, let last = result.last, last.location == NSMaxRange(range) {
            result.removeLast()
        }
        return result
    }

    /// The line (without terminator) containing `location`.
    func lineContentRange(at location: Int) -> NSRange {
        var start = 0, end = 0, contentsEnd = 0
        getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }
}

nonisolated extension String {
    var utf16Length: Int { (self as NSString).length }
}
