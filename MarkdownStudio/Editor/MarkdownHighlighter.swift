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

    /// Every color that draws text reaches at least 4.5:1 on the editor (and code)
    /// background in light and dark mode, and more with Increase Contrast.
    enum Colors {
        static let text = NSColor.textColor
        static let syntax = adaptive("syntax", Swatch.syntax)
        static let secondary = adaptive("secondary", Swatch.secondary)
        static let link = NSColor.linkColor
        static let code = adaptive("code", Swatch.code)
        static let codeBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.08)
        static let listMarker = adaptive("listMarker", Swatch.listMarker)
        static let html = adaptive("html", Swatch.html)
        static let math = adaptive("math", Swatch.math)
        static let highlight = NSColor.systemYellow.withAlphaComponent(0.3)
        /// Line numbers in the gutter.
        static let lineNumber = syntax

        /// sRGB values for light, dark, and both with Increase Contrast.
        struct Swatch: Sendable {
            var light: Int, dark: Int, lightHigh: Int, darkHigh: Int

            static let syntax = Swatch(light: 0x6B6B70, dark: 0x9B9BA1, lightHigh: 0x4A4A4F, darkHigh: 0xC0C0C6)
            static let secondary = Swatch(light: 0x5F5F64, dark: 0xA8A8AE, lightHigh: 0x3F3F44, darkHigh: 0xCACACF)
            static let code = Swatch(light: 0xB01A66, dark: 0xFF7EB3, lightHigh: 0x8A0F4E, darkHigh: 0xFFA3CA)
            static let listMarker = Swatch(light: 0xA64B00, dark: 0xFFA94D, lightHigh: 0x7F3900, darkHigh: 0xFFC27F)
            static let html = Swatch(light: 0x00727C, dark: 0x5FD3DE, lightHigh: 0x00565E, darkHigh: 0x8BE5EE)
            static let math = Swatch(light: 0x7B2FB8, dark: 0xC79BFF, lightHigh: 0x5E1F92, darkHigh: 0xD9BBFF)
            static let all: [(String, Swatch)] = [("syntax", syntax), ("secondary", secondary), ("code", code),
                                                  ("listMarker", listMarker), ("html", html), ("math", math)]

            func value(dark isDark: Bool, highContrast: Bool) -> Int {
                switch (isDark, highContrast) {
                case (false, false): light
                case (true, false): dark
                case (false, true): lightHigh
                case (true, true): darkHigh
                }
            }
        }

        /// Resolved at draw time, so it follows Light/Dark and Increase Contrast
        /// (which macOS reports as a setting, not as the appearance's name).
        private static func adaptive(_ name: String, _ swatch: Swatch) -> NSColor {
            NSColor(name: "MarkdownStudio.\(name)") { appearance in
                let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
                let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
                let highContrast = match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
                    || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                return rgb(swatch.value(dark: isDark, highContrast: highContrast))
            }
        }

        private static func rgb(_ hex: Int) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
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
        if newCodeRanges != codeRanges {
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
