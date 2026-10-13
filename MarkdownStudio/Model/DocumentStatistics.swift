import Foundation

nonisolated struct DocumentStatistics: Equatable, Sendable {
    var words = 0
    var characters = 0
    var lines = 1

    /// Rounded-up minutes at ~225 words per minute.
    var readingMinutes: Int { words == 0 ? 0 : max(1, Int((Double(words) / 225).rounded(.up))) }

    init() {}

    init(_ text: String) {
        characters = text.count
        lines = text.utf16.reduce(1) { $1 == 0x0A ? $0 + 1 : $0 }
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        words = count
    }
}
