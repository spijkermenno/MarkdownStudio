import Foundation

/// Heading IDs, matching `Web/render.js` so links built in Swift (table of
/// contents, autocomplete, document check) point at the right headings.
nonisolated enum HeadingSlug {
    static func slugify(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        s = s.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[^\\p{L}\\p{N}\\s_-]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
        return s
    }

    /// Unique IDs in document order: custom `{#id}` wins, duplicates get `-1`, `-2`, ….
    static func uniqueIDs(_ headings: [(title: String, customID: String?)]) -> [String] {
        var used = Set<String>()
        return headings.map { heading in
            let base = heading.customID ?? {
                // Emoji shortcodes render as emoji, which the slug drops.
                let text = heading.title.replacingOccurrences(of: ":[a-z0-9_+-]+:", with: "", options: .regularExpression)
                let slug = slugify(text)
                return slug.isEmpty ? "section" : slug
            }()
            var unique = base
            var n = 1
            while used.contains(unique) {
                unique = "\(base)-\(n)"
                n += 1
            }
            used.insert(unique)
            return unique
        }
    }
}
