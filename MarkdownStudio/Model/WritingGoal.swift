import Foundation

/// Word goals and "words written today", stored per file path in UserDefaults.
/// A `goal:` key in the document's front matter takes precedence.
nonisolated enum WritingGoal {
    private static let goalsKey = "writingGoals"
    private static let baselinesKey = "writingBaselines"

    static func frontMatterGoal(in text: String) -> Int? {
        guard let range = MarkdownHighlighter.frontMatterRange(in: text) else { return nil }
        let frontMatter = (text as NSString).substring(with: range)
        guard let match = frontMatter.range(of: "(?m)^goal:[ \\t]*(\\d+)[ \\t]*$", options: .regularExpression) else { return nil }
        return Int(frontMatter[match].filter(\.isNumber))
    }

    /// Replaces the `goal:` line in front matter (or removes it when `goal` is nil).
    static func frontMatterEdit(in text: String, goal: Int?) -> TextEdit? {
        guard let range = MarkdownHighlighter.frontMatterRange(in: text) else { return nil }
        let ns = text as NSString
        let lineRange = ns.range(of: "(?m)^goal:[^\\n]*\\n?", options: .regularExpression, range: range)
        guard lineRange.location != NSNotFound else { return nil }
        let replacement = goal.map { "goal: \($0)\n" } ?? ""
        return TextEdit(range: lineRange, replacement: replacement, selection: NSRange(location: lineRange.location, length: 0))
    }

    static func storedGoal(for url: URL) -> Int? {
        let goals = UserDefaults.standard.dictionary(forKey: goalsKey) as? [String: Int]
        return goals?[url.standardizedFileURL.path]
    }

    static func store(_ goal: Int?, for url: URL) {
        var goals = (UserDefaults.standard.dictionary(forKey: goalsKey) as? [String: Int]) ?? [:]
        goals[url.standardizedFileURL.path] = goal
        UserDefaults.standard.set(goals, forKey: goalsKey)
    }

    /// Words written today: the difference with the first count seen today.
    static func wordsToday(current: Int, for key: String, now: Date = Date()) -> Int {
        let day = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: [.withFullDate])
        var baselines = (UserDefaults.standard.dictionary(forKey: baselinesKey) as? [String: [String: Any]]) ?? [:]
        if let entry = baselines[key], entry["day"] as? String == day, let start = entry["words"] as? Int {
            return current - start
        }
        // Drop entries from earlier days so the dictionary doesn't grow forever.
        baselines = baselines.filter { $0.value["day"] as? String == day }
        baselines[key] = ["day": day, "words": current]
        UserDefaults.standard.set(baselines, forKey: baselinesKey)
        return 0
    }
}
