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

    /// The text markdown-it would slug for a raw heading: images dropped,
    /// inline Markdown removed and HTML entities decoded.
    static func text(fromHeading raw: String) -> String {
        var s = raw.replacingOccurrences(of: "\\s*\\{#[\\w\\-:.]+\\}\\s*$", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^)]*\\)", with: "", options: .regularExpression)
        s = OutlineParser.strip(s)
        return decodeEntities(s)
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var s = text
        let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "]
        for (entity, value) in named { s = s.replacingOccurrences(of: entity, with: value) }
        let numeric = try! NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")
        for match in numeric.matches(in: s, range: NSRange(location: 0, length: s.utf16Length)).reversed() {
            let ns = s as NSString
            let isHex = match.range(at: 1).length > 0
            guard let value = UInt32(ns.substring(with: match.range(at: 2)), radix: isHex ? 16 : 10),
                  let scalar = Unicode.Scalar(value) else { continue }
            s = ns.replacingCharacters(in: match.range, with: String(Character(scalar)))
        }
        return s
    }

    /// Unique IDs in document order: custom `{#id}` wins, duplicates get `-1`, `-2`, ….
    static func uniqueIDs(_ headings: [(title: String, customID: String?)]) -> [String] {
        var used = Set<String>()
        return headings.map { heading in
            let base = heading.customID ?? {
                let slug = slugify(heading.title)
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
