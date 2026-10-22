import Foundation

/// Subsequence matching for Quick Open: "rel pl" finds "release-plan.md".
/// Consecutive letters, word starts and file-name matches score higher.
nonisolated enum FuzzyMatcher {
    static func score(_ query: String, in candidate: String, fileName: String) -> Int? {
        let terms = query.lowercased().split(separator: " ").map(Array.init)
        guard !terms.isEmpty else { return 0 }
        let haystack = Array(candidate.lowercased())
        let name = fileName.lowercased()
        var total = 0
        for term in terms {
            guard let s = subsequenceScore(term, haystack) else { return nil }
            total += s
            if name.contains(String(term)) { total += 25 }
            if name.hasPrefix(String(term)) { total += 15 }
        }
        return total - candidate.count / 8
    }

    private static func subsequenceScore(_ term: [Character], _ haystack: [Character]) -> Int? {
        var score = 0
        var index = 0
        var previousMatch = -2
        for ch in term {
            guard let found = haystack[index...].firstIndex(of: ch) else { return nil }
            score += 1
            if found == previousMatch + 1 { score += 5 }
            if found == 0 || "/-_ .".contains(haystack[found - 1]) { score += 8 }
            previousMatch = found
            index = found + 1
        }
        return score
    }
}
