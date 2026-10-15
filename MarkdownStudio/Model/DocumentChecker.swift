import Foundation

nonisolated struct DocumentProblem: Identifiable, Hashable, Sendable {
    enum Severity: Sendable { case warning, info }

    struct Fix: Hashable, Sendable {
        var title: String
        var edit: TextEdit
    }

    var range: NSRange
    var line: Int
    var message: String
    var severity: Severity
    var fix: Fix?
    var id: String { "\(range.location):\(range.length):\(message)" }
}

/// Finds broken links and images, unknown anchors, footnote mistakes and
/// heading-structure issues. Code blocks, inline code, HTML comments and
/// front matter are ignored.
nonisolated enum DocumentChecker {
    struct FileSystem: Sendable {
        var fileExists: @Sendable (URL) -> Bool
        var filesInDirectory: @Sendable (URL) -> [String]

        static let live = FileSystem(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            filesInDirectory: { (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) ?? [] }
        )
    }

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let inlineLink = regex(#"(!?)\[((?:[^\[\]\n]|\[[^\]\n]*\])*)\]\(\s*(<[^>\n]*>|[^)\s]*)(?:\s+(?:"[^"\n]*"|'[^'\n]*'|\([^)\n]*\)))?\s*\)"#)
    private static let referenceLink = regex(#"(?<![\]\\])\[((?:[^\[\]\n]|\[[^\]\n]*\])+)\]\[([^\]\n]*)\]"#)
    private static let referenceDefinition = regex(#"^ {0,3}\[(?!\^)([^\]\n]+)\]:[ \t]*\S"#, [.anchorsMatchLines])
    private static let footnoteReference = regex(#"\[\^([^\]\s]+)\](?!:)"#)
    private static let footnoteDefinition = regex(#"^ {0,3}\[\^([^\]\s]+)\]:"#, [.anchorsMatchLines])
    private static let htmlID = regex(#"\b(?:id|name)\s*=\s*["']([^"']+)["']"#)
    private static let inlineCode = regex(#"(`+)(?!`)[\s\S]*?(?<!`)\1(?!`)"#)
    private static let htmlComment = regex(#"<!--[\s\S]*?-->"#)

    static func check(_ text: String, documentDirectory: URL?, fileSystem: FileSystem = .live) -> [DocumentProblem] {
        let ns = text as NSString
        let masked = mask(text)
        let full = NSRange(location: 0, length: ns.length)
        let lineIndex = LineIndex(text)
        var problems: [DocumentProblem] = []

        func add(_ range: NSRange, _ message: String, _ severity: DocumentProblem.Severity, fix: DocumentProblem.Fix? = nil) {
            problems.append(DocumentProblem(range: range, line: lineIndex.line(containing: range.location),
                                            message: message, severity: severity, fix: fix))
        }

        // Known anchors: headings plus explicit HTML ids.
        let outline = OutlineParser.parse(text)
        var anchors = Set(outline.map(\.anchor))
        htmlID.enumerateMatches(in: text, range: full) { m, _, _ in
            if let m { anchors.insert(ns.substring(with: m.range(at: 1))) }
        }

        // Inline links and images.
        inlineLink.enumerateMatches(in: masked, range: full) { m, _, _ in
            guard let m else { return }
            let isImage = m.range(at: 1).length > 0
            let label = ns.substring(with: m.range(at: 2))
            var destinationRange = m.range(at: 3)
            var destination = ns.substring(with: destinationRange)
            if destination.hasPrefix("<") && destination.hasSuffix(">") {
                destination = String(destination.dropFirst().dropLast())
                destinationRange = NSRange(location: destinationRange.location + 1, length: max(0, destinationRange.length - 2))
            }

            if label.trimmingCharacters(in: .whitespaces).isEmpty {
                add(m.range, isImage ? "Image has no alt text (used by screen readers)" : "Link has no text", .info)
            }
            if destination.isEmpty {
                add(m.range, isImage ? "Image has no source" : "Link has no destination", .warning)
                return
            }
            if destination.hasPrefix("#") {
                let anchor = String(destination.dropFirst()).removingPercentEncoding ?? String(destination.dropFirst())
                if !anchor.isEmpty, !anchors.contains(anchor) {
                    var fix: DocumentProblem.Fix?
                    if let suggestion = closest(to: anchor, in: anchors) {
                        let range = NSRange(location: destinationRange.location + 1, length: destinationRange.length - 1)
                        fix = .init(title: "Use #\(suggestion)", edit: TextEdit(range: range, replacement: suggestion,
                                                                                 selection: NSRange(location: range.location, length: suggestion.utf16Length)))
                    }
                    let hint = fix.map { _ in " Did you mean “\(closest(to: anchor, in: anchors)!)”?" } ?? ""
                    add(destinationRange, "No heading with ID “\(anchor)”.\(hint)", .warning, fix: fix)
                }
                return
            }
            // URLs with a scheme (https:, mailto:, …) aren't checked.
            if destination.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) != nil,
               !destination.lowercased().hasPrefix("file:") { return }
            guard let documentDirectory else { return }

            let pathPart = destination.components(separatedBy: CharacterSet(charactersIn: "#?")).first ?? destination
            let decoded = pathPart.removingPercentEncoding ?? pathPart
            guard !decoded.isEmpty else { return }
            let target: URL
            if decoded.lowercased().hasPrefix("file://") {
                target = URL(string: pathPart) ?? URL(filePath: decoded)
            } else if decoded.hasPrefix("/") {
                target = URL(filePath: decoded)
            } else {
                target = documentDirectory.appending(path: decoded).standardizedFileURL
            }
            guard !fileSystem.fileExists(target) else { return }

            var fix: DocumentProblem.Fix?
            let name = target.lastPathComponent
            let siblings = fileSystem.filesInDirectory(target.deletingLastPathComponent())
            if let suggestion = closest(to: name, in: Set(siblings)) {
                let encodedName = (pathPart as NSString).lastPathComponent
                let nameRange = (destination as NSString).range(of: encodedName, options: .backwards)
                if nameRange.location != NSNotFound {
                    let encodedSuggestion = suggestion.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? suggestion
                    let range = NSRange(location: destinationRange.location + nameRange.location, length: nameRange.length)
                    fix = .init(title: "Use “\(suggestion)”", edit: TextEdit(range: range, replacement: encodedSuggestion,
                                                                            selection: NSRange(location: range.location, length: encodedSuggestion.utf16Length)))
                }
            }
            add(destinationRange, "\(isImage ? "Image" : "File") not found: \(decoded)", .warning, fix: fix)
        }

        // Reference-style links.
        var definitions = Set<String>()
        referenceDefinition.enumerateMatches(in: masked, range: full) { m, _, _ in
            if let m { definitions.insert(normalizeLabel(ns.substring(with: m.range(at: 1)))) }
        }
        referenceLink.enumerateMatches(in: masked, range: full) { m, _, _ in
            guard let m else { return }
            let text = ns.substring(with: m.range(at: 1))
            guard !text.hasPrefix("^") else { return }
            let reference = ns.substring(with: m.range(at: 2))
            let label = normalizeLabel(reference.isEmpty ? text : reference)
            if !definitions.contains(label) {
                add(m.range, "No link definition for [\(reference.isEmpty ? text : reference)]", .warning)
            }
        }

        // Footnotes.
        var footnoteDefinitions: [String: NSRange] = [:]
        footnoteDefinition.enumerateMatches(in: masked, range: full) { m, _, _ in
            if let m { footnoteDefinitions[ns.substring(with: m.range(at: 1))] = m.range }
        }
        var referenced = Set<String>()
        var missing: [String: NSRange] = [:]
        footnoteReference.enumerateMatches(in: masked, range: full) { m, _, _ in
            guard let m else { return }
            let id = ns.substring(with: m.range(at: 1))
            referenced.insert(id)
            if footnoteDefinitions[id] == nil, missing[id] == nil { missing[id] = m.range }
        }
        for (id, range) in missing.sorted(by: { $0.value.location < $1.value.location }) {
            let suffix = text.hasSuffix("\n") ? "" : "\n"
            let definition = "\(suffix)\n[^\(id)]: "
            let fix = DocumentProblem.Fix(title: "Add definition", edit: TextEdit(
                range: NSRange(location: ns.length, length: 0), replacement: definition,
                selection: NSRange(location: ns.length + definition.utf16Length, length: 0)))
            add(range, "Footnote [^\(id)] has no definition", .warning, fix: fix)
        }
        for (id, range) in footnoteDefinitions.sorted(by: { $0.value.location < $1.value.location }) where !referenced.contains(id) {
            add(range, "Footnote [^\(id)] is never referenced", .info)
        }

        // Heading structure.
        var previousLevel: Int?
        var seen: [String: Int] = [:]
        for item in outline {
            let range = ns.lineContentRange(at: lineIndex.start(ofLine: item.line))
            if let previous = previousLevel, item.level > previous + 1 {
                add(range, "Heading jumps from H\(previous) to H\(item.level)", .info)
            }
            previousLevel = item.level
            let key = item.title.lowercased()
            if let first = seen[key] {
                add(range, "Duplicate heading “\(item.title)” (also on line \(first + 1)); #links go to the first one", .info)
            } else {
                seen[key] = item.line
            }
        }

        return problems.sorted { $0.range.location < $1.range.location }
    }

    // MARK: - Helpers

    /// Replaces code, comments and front matter with spaces (keeping offsets and newlines).
    static func mask(_ text: String) -> String {
        let masked = NSMutableString(string: text)
        func blank(_ range: NSRange) {
            guard range.length > 0 else { return }
            // One replacement unit per UTF-16 unit, keeping \r and \n, so offsets and lines stay intact.
            let units = masked.substring(with: range).utf16.map { $0 == 0x0A || $0 == 0x0D ? $0 : 0x20 }
            masked.replaceCharacters(in: range, with: String(utf16CodeUnits: units, count: units.count))
        }
        if let fm = MarkdownHighlighter.frontMatterRange(in: text) { blank(fm) }
        for range in MarkdownHighlighter.fencedCodeRanges(in: text) { blank(range) }
        for pattern in [htmlComment, inlineCode] {
            let snapshot = masked as String
            pattern.enumerateMatches(in: snapshot, range: NSRange(location: 0, length: masked.length)) { m, _, _ in
                if let m { blank(m.range) }
            }
        }
        return masked as String
    }

    private static func normalizeLabel(_ label: String) -> String {
        label.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The candidate with the smallest edit distance, if it's close enough to be a likely typo.
    static func closest(to target: String, in candidates: Set<String>) -> String? {
        let lower = target.lowercased()
        let best = candidates
            .map { ($0, distance(lower, $0.lowercased())) }
            .min { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }
        guard let best, best.1 > 0, best.1 <= max(2, target.count / 4) else { return nil }
        return best.0
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
