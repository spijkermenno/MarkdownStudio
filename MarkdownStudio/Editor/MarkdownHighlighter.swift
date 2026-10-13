import AppKit

/// Regex-based Markdown syntax highlighting for the editor's text storage.
///
/// Line-local rules are re-applied only to the edited paragraphs; the whole
/// document is re-highlighted when fenced code blocks change, because opening
/// or closing a fence affects everything after it.
@MainActor
final class MarkdownHighlighter {
    private(set) var configuration = EditorConfiguration()
    private var fonts = Fonts(base: .monospacedSystemFont(ofSize: 14, weight: .regular))
    private var codeRanges: [NSRange] = []

    private struct Fonts {
        let base: NSFont
        let bold: NSFont
        let italic: NSFont
        let boldItalic: NSFont
        let headings: [NSFont]

        init(base: NSFont) {
            let manager = NSFontManager.shared
            self.base = base
            bold = manager.convert(base, toHaveTrait: .boldFontMask)
            italic = manager.convert(base, toHaveTrait: .italicFontMask)
            boldItalic = manager.convert(bold, toHaveTrait: .italicFontMask)
            let scales: [CGFloat] = [1.4, 1.25, 1.12, 1.05, 1, 1]
            let boldBase = bold
            headings = scales.map { manager.convert(boldBase, toSize: (base.pointSize * $0).rounded()) }
        }
    }

    enum Colors {
        static let text = NSColor.textColor
        static let syntax = NSColor.tertiaryLabelColor
        static let secondary = NSColor.secondaryLabelColor
        static let link = NSColor.linkColor
        static let code = NSColor.systemPink
        static let codeBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.08)
        static let listMarker = NSColor.systemOrange
        static let html = NSColor.systemTeal
        static let math = NSColor.systemPurple
        static let highlight = NSColor.systemYellow.withAlphaComponent(0.3)
    }

    func configure(_ configuration: EditorConfiguration) {
        self.configuration = configuration
        fonts = Fonts(base: configuration.font)
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.15
        return [.font: fonts.base, .foregroundColor: Colors.text, .paragraphStyle: paragraph]
    }

    // MARK: - Entry points

    func highlightAll(_ storage: NSTextStorage) {
        codeRanges = Self.fencedCodeRanges(in: storage.string)
        highlight(storage, in: NSRange(location: 0, length: storage.length))
    }

    /// Re-highlights after an edit in `editedRange`.
    func highlightEdit(_ storage: NSTextStorage, editedRange: NSRange) {
        let newCodeRanges = Self.fencedCodeRanges(in: storage.string)
        if newCodeRanges.count != codeRanges.count || zip(newCodeRanges, codeRanges).contains(where: { $0.location != $1.location }) {
            codeRanges = newCodeRanges
            highlight(storage, in: NSRange(location: 0, length: storage.length))
            return
        }
        codeRanges = newCodeRanges
        let ns = storage.string as NSString
        // Include neighbouring lines for setext headings and multi-line constructs.
        var range = ns.paragraphRange(for: editedRange)
        if range.location > 0 { range = NSUnionRange(range, ns.paragraphRange(for: NSRange(location: range.location - 1, length: 0))) }
        if NSMaxRange(range) < ns.length { range = NSUnionRange(range, ns.paragraphRange(for: NSRange(location: NSMaxRange(range), length: 0))) }
        highlight(storage, in: range)
    }

    // MARK: - Highlighting

    private func highlight(_ storage: NSTextStorage, in range: NSRange) {
        guard range.length > 0 || storage.length == 0 else { return }
        storage.beginEditing()
        defer { storage.endEditing() }

        storage.setAttributes(baseAttributes, range: range)
        guard configuration.syntaxHighlighting else { return }

        let string = storage.string
        func each(_ regex: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            regex.enumerateMatches(in: string, range: range) { match, _, _ in
                if let match { body(match) }
            }
        }
        func color(_ range: NSRange, _ color: NSColor) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            storage.addAttribute(.foregroundColor, value: color, range: range)
        }
        func font(_ range: NSRange, _ font: NSFont) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            storage.addAttribute(.font, value: font, range: range)
        }
        /// Adds a font trait while keeping existing traits (bold inside italic, …).
        func addTrait(_ range: NSRange, _ trait: NSFontTraitMask) {
            storage.enumerateAttribute(.font, in: range) { value, sub, _ in
                let current = value as? NSFont ?? fonts.base
                storage.addAttribute(.font, value: NSFontManager.shared.convert(current, toHaveTrait: trait), range: sub)
            }
        }

        // Block-level
        each(Rules.atxHeading) { m in
            let level = m.range(at: 1).length
            font(m.range, fonts.headings[level - 1])
            color(m.range(at: 1), Colors.syntax)
            color(m.range(at: 3), Colors.syntax)
        }
        each(Rules.setextHeading) { m in
            let level = (string as NSString).substring(with: m.range(at: 2)).hasPrefix("=") ? 1 : 2
            font(m.range(at: 1), fonts.headings[level - 1])
            color(m.range(at: 2), Colors.syntax)
        }
        each(Rules.blockquote) { m in
            color(m.range, Colors.secondary)
            color(m.range(at: 1), Colors.syntax)
        }
        each(Rules.listMarker) { m in color(m.range(at: 1), Colors.listMarker) }
        each(Rules.taskBox) { m in color(m.range(at: 1), Colors.listMarker) }
        each(Rules.horizontalRule) { m in color(m.range, Colors.syntax) }
        each(Rules.referenceDefinition) { m in color(m.range, Colors.secondary) }
        each(Rules.footnoteDefinition) { m in color(m.range(at: 1), Colors.link) }
        each(Rules.definitionMarker) { m in color(m.range(at: 1), Colors.listMarker) }
        each(Rules.tablePipe) { m in color(m.range, Colors.syntax) }

        // Inline
        each(Rules.html) { m in color(m.range, Colors.html) }
        each(Rules.boldItalic) { m in
            addTrait(m.range, .boldFontMask); addTrait(m.range, .italicFontMask)
            color(m.range(at: 1), Colors.syntax); color(m.range(at: 3), Colors.syntax)
        }
        each(Rules.bold) { m in
            addTrait(m.range, .boldFontMask)
            color(m.range(at: 1), Colors.syntax); color(m.range(at: 3), Colors.syntax)
        }
        each(Rules.italic) { m in
            addTrait(m.range, .italicFontMask)
            color(m.range(at: 1), Colors.syntax); color(m.range(at: 3), Colors.syntax)
        }
        each(Rules.strikethrough) { m in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 2))
            color(m.range, Colors.secondary)
        }
        each(Rules.highlight) { m in
            storage.addAttribute(.backgroundColor, value: Colors.highlight, range: m.range(at: 2))
            color(m.range(at: 1), Colors.syntax); color(m.range(at: 3), Colors.syntax)
        }
        each(Rules.subSup) { m in color(m.range(at: 1), Colors.syntax); color(m.range(at: 3), Colors.syntax) }
        each(Rules.link) { m in
            color(m.range, Colors.syntax)
            color(m.range(at: 1), Colors.link)
            color(m.range(at: 2), Colors.secondary)
        }
        each(Rules.referenceLink) { m in
            color(m.range, Colors.syntax)
            color(m.range(at: 1), Colors.link)
        }
        each(Rules.autolink) { m in
            color(m.range, Colors.link)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: m.range)
        }
        each(Rules.footnoteReference) { m in color(m.range, Colors.link) }
        each(Rules.emoji) { m in color(m.range, Colors.secondary) }
        each(Rules.mathInline) { m in color(m.range, Colors.math) }
        each(Rules.inlineCode) { m in
            storage.setAttributes(baseAttributes, range: m.range)
            color(m.range, Colors.code)
            storage.addAttribute(.backgroundColor, value: Colors.codeBackground, range: m.range)
        }
        each(Rules.escape) { m in color(m.range, Colors.syntax) }

        // Code and math blocks override everything inside them.
        for block in codeRanges where NSIntersectionRange(block, range).length > 0 || NSLocationInRange(range.location, block) {
            let target = NSIntersectionRange(block, NSRange(location: 0, length: storage.length))
            storage.setAttributes(baseAttributes, range: target)
            color(target, Colors.code)
            storage.addAttribute(.backgroundColor, value: Colors.codeBackground, range: target)
        }
        each(Rules.mathBlock) { m in
            storage.setAttributes(baseAttributes, range: m.range)
            color(m.range, Colors.math)
        }

        // Front matter is YAML, not Markdown.
        if let fm = Self.frontMatterRange(in: string), NSIntersectionRange(fm, range).length > 0 {
            let target = NSIntersectionRange(fm, range)
            storage.setAttributes(baseAttributes, range: target)
            color(target, Colors.secondary)
        }
    }

    // MARK: - Rules

    private enum Rules {
        static func regex(_ pattern: String, _ options: NSRegularExpression.Options = [.anchorsMatchLines]) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: options)
        }

        static let atxHeading = regex("^ {0,3}(#{1,6})([ \\t]+.*?)??([ \\t]+#+)?[ \\t]*$")
        static let setextHeading = regex("^(?! {0,3}(?:[-*+>]|\\d+[.)])[ \\t])(\\S.*)\\n {0,3}(=+|-+)[ \\t]*$")
        static let blockquote = regex("^[ \\t]*((?:>[ \\t]?)+).*$")
        static let listMarker = regex("^[ \\t]*([-*+]|\\d{1,9}[.)])[ \\t]+")
        static let taskBox = regex("^[ \\t]*(?:[-*+]|\\d{1,9}[.)])[ \\t]+(\\[[ xX]\\])")
        static let horizontalRule = regex("^ {0,3}([-*_])(?:[ \\t]*\\1){2,}[ \\t]*$")
        static let referenceDefinition = regex("^ {0,3}\\[(?!\\^)[^\\]]+\\]:[ \\t]+\\S.*$")
        static let footnoteDefinition = regex("^ {0,3}(\\[\\^[^\\]]+\\]:)")
        static let definitionMarker = regex("^(:)[ \\t]+")
        static let tablePipe = regex("(?<!\\\\)\\|")

        static let html = regex("</?[A-Za-z][A-Za-z0-9-]*(?:\\s[^<>]*)?/?>|<!--[\\s\\S]*?-->", [])
        static let boldItalic = regex("(\\*\\*\\*|___)(?=\\S)(.+?)(?<=\\S)(\\1)")
        static let bold = regex("(?<![*_\\\\])(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)(\\1)(?![*_])")
        static let italic = regex("(?<![*\\\\\\w])(\\*|_)(?=[^\\s*_])(.+?)(?<=[^\\s*_\\\\])(\\1)(?![*\\w])")
        static let strikethrough = regex("(~~)(?=\\S)(.+?)(?<=\\S)(~~)")
        static let highlight = regex("(==)(?=\\S)(.+?)(?<=\\S)(==)")
        static let subSup = regex("(?<![~^\\\\])([~^])(?=\\S)([^\\s~^]+)(?<=\\S)(\\1)(?![~^])")
        static let link = regex("!?\\[([^\\]\\n]*)\\]\\(([^)\\n]*)\\)")
        static let referenceLink = regex("!?\\[([^\\]\\n]+)\\]\\[[^\\]\\n]*\\]")
        static let autolink = regex("<(?:https?|ftp|mailto):[^>\\s]+>|<[^@>\\s]+@[^@>\\s]+\\.[^@>\\s]+>|(?<![(<\\[\"'=])\\bhttps?://[^\\s<>()\\[\\]]+[^\\s<>()\\[\\].,;:!?\"']")
        static let footnoteReference = regex("\\[\\^[^\\]\\s]+\\](?!:)")
        static let emoji = regex("(?<![\\w:]):[a-z0-9_+-]+:(?![\\w:])")
        static let mathInline = regex("(?<![\\\\$])\\$(?=\\S)[^$\\n]+?(?<=\\S)\\$(?![\\d$])")
        static let mathBlock = regex("^[ \\t]*\\$\\$[\\s\\S]*?\\$\\$[ \\t]*$")
        static let inlineCode = regex("(?<!`)(`+)(?!`).+?(?<!`)\\1(?!`)")
        static let escape = regex("\\\\[\\\\`*_{}\\[\\]<>()#+\\-.!|~=^$]")
    }

    // MARK: - Block scanning

    nonisolated static func fencedCodeRanges(in string: String) -> [NSRange] {
        var ranges: [NSRange] = []
        var open: (marker: Character, count: Int, start: Int)?
        var location = 0
        for line in string.split(separator: "\n", omittingEmptySubsequences: false) {
            let length = line.utf16.count
            let trimmed = line.drop(while: { $0 == " " })
            if line.count - trimmed.count <= 3, let first = trimmed.first, first == "`" || first == "~" {
                let run = trimmed.prefix(while: { $0 == first }).count
                if run >= 3 {
                    if let current = open {
                        if first == current.marker, run >= current.count,
                           trimmed.dropFirst(run).allSatisfy({ $0 == " " || $0 == "\t" || $0 == "\r" }) {
                            ranges.append(NSRange(location: current.start, length: location + length - current.start))
                            open = nil
                        }
                    } else if first == "~" || !trimmed.dropFirst(run).contains("`") {
                        open = (first, run, location)
                    }
                }
            }
            location += length + 1
        }
        if let current = open {
            ranges.append(NSRange(location: current.start, length: max(0, (string as NSString).length - current.start)))
        }
        return ranges
    }

    nonisolated static func frontMatterRange(in string: String) -> NSRange? {
        guard string.hasPrefix("---\n") || string.hasPrefix("---\r\n") else { return nil }
        let ns = string as NSString
        let search = NSRange(location: 3, length: ns.length - 3)
        let close = ns.range(of: "\n(---|\\.\\.\\.)[ \\t]*(\\r?\\n|$)", options: .regularExpression, range: search)
        guard close.location != NSNotFound else { return nil }
        return NSRange(location: 0, length: NSMaxRange(close))
    }
}
