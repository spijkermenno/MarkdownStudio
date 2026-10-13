import Foundation

/// Maps between UTF-16 offsets and zero-based line numbers. Line numbers match
/// markdown-it's source map, so they can be exchanged with the preview.
nonisolated struct LineIndex: Sendable {
    private(set) var starts: [Int] = [0]
    let length: Int

    init(_ text: String) {
        var starts = [0]
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 0x0A { starts.append(offset) }
        }
        self.starts = starts
        self.length = offset
    }

    var lineCount: Int { starts.count }

    func start(ofLine line: Int) -> Int {
        starts[max(0, min(line, starts.count - 1))]
    }

    /// The range of a line including its terminator.
    func range(ofLine line: Int) -> NSRange {
        let clamped = max(0, min(line, starts.count - 1))
        let start = starts[clamped]
        let end = clamped + 1 < starts.count ? starts[clamped + 1] : length
        return NSRange(location: start, length: end - start)
    }

    func line(containing offset: Int) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }
}
