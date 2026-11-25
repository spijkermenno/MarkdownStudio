import Foundation

nonisolated struct OutlineItem: Identifiable, Hashable, Sendable {
    var level: Int
    var title: String
    /// Zero-based source line.
    var line: Int
    /// The heading's HTML id in the preview (same algorithm as render.js).
    var anchor: String = ""
    var id: Int { line }
}

/// Extracts headings (ATX and setext) for the outline sidebar, skipping code
/// blocks and front matter.
nonisolated enum OutlineParser {
    private static let atx = try! NSRegularExpression(pattern: "^ {0,3}(#{1,6})(?:[ \\t]+(.*?))?(?:[ \\t]+#+)?[ \\t]*$")
    private static let setext = try! NSRegularExpression(pattern: "^ {0,3}(=+|-+)[ \\t]*$")
    private static let fence = try! NSRegularExpression(pattern: "^ {0,3}(`{3,}|~{3,})")
    private static let listOrQuote = try! NSRegularExpression(pattern: "^ {0,3}(?:[-*+>]|\\d+[.)])(?:[ \\t]|$)")

    static func parse(_ text: String) -> [OutlineItem] {
        let lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var items: [OutlineItem] = []
        var customIDs: [String?] = []
        var slugTexts: [String] = []
        var fenceMarker: String?
        var start = 0

        // Skip YAML front matter.
        if lines.first == "---", let end = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) {
            start = end + 1
        }

        var previousIsParagraph = false
        var i = start
        while i < lines.count {
            let line = lines[i]
            let range = NSRange(location: 0, length: line.utf16Length)

            if let m = fence.firstMatch(in: line, range: range) {
                let marker = (line as NSString).substring(with: m.range(at: 1))
                if let open = fenceMarker {
                    if marker.first == open.first && marker.count >= open.count
                        && line.trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == open.first }) {
                        fenceMarker = nil
                    }
                } else {
                    fenceMarker = marker
                }
                previousIsParagraph = false
                i += 1
                continue
            }
            if fenceMarker != nil { i += 1; continue }

            if let m = atx.firstMatch(in: line, range: range) {
                let level = m.range(at: 1).length
                let title = m.range(at: 2).location != NSNotFound ? (line as NSString).substring(with: m.range(at: 2)) : ""
                items.append(OutlineItem(level: level, title: clean(title), line: i))
                customIDs.append(customID(title))
                slugTexts.append(HeadingSlug.text(fromHeading: title))
                previousIsParagraph = false
            } else if previousIsParagraph, let m = setext.firstMatch(in: line, range: range) {
                let level = (line as NSString).substring(with: m.range(at: 1)).hasPrefix("=") ? 1 : 2
                items.append(OutlineItem(level: level, title: clean(lines[i - 1]), line: i - 1))
                customIDs.append(customID(lines[i - 1]))
                slugTexts.append(HeadingSlug.text(fromHeading: lines[i - 1]))
                previousIsParagraph = false
            } else {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                previousIsParagraph = !trimmed.isEmpty && !line.hasPrefix("    ") && !line.hasPrefix("\t")
                    && listOrQuote.firstMatch(in: line, range: range) == nil
            }
            i += 1
        }
        let anchors = HeadingSlug.uniqueIDs(items.indices.map { (slugTexts[$0], customIDs[$0]) })
        for index in items.indices { items[index].anchor = anchors[index] }
        return items
    }

    private static func customID(_ title: String) -> String? {
        guard let match = title.range(of: "\\{#([\\w\\-:.]+)\\}\\s*$", options: .regularExpression) else { return nil }
        return String(title[match]).trimmingCharacters(in: CharacterSet(charactersIn: "{}# \t"))
    }

    /// Strips inline Markdown so the outline shows plain titles.
    static func clean(_ title: String) -> String {
        let s = strip(title)
        return s.isEmpty ? "Untitled" : s
    }

    /// Inline Markdown removed, without the "Untitled" placeholder.
    static func strip(_ title: String) -> String {
        var s = title.trimmingCharacters(in: .whitespaces)
        let replacements: [(String, String)] = [
            ("\\s*\\{#[\\w\\-:.]+\\}\\s*$", ""),            // custom heading id
            ("!?\\[([^\\]]*)\\]\\([^)]*\\)", "$1"),         // links and images
            ("\\[([^\\]]*)\\]\\[[^\\]]*\\]", "$1"),         // reference links
            ("(\\*\\*|__|~~|==)(.+?)\\1", "$2"),             // bold, strike, highlight
            ("(?<![\\w*])[*_](.+?)[*_](?![\\w*])", "$1"),    // italic
            ("`([^`]*)`", "$1"),                             // code
            ("<[^>]+>", ""),                                 // html
        ]
        for (pattern, template) in replacements {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return s
    }
}
