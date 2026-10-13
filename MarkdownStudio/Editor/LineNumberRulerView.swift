import AppKit

/// Draws source line numbers beside the editor (TextKit 1).
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    var lineIndex = LineIndex("") {
        didSet { updateThickness() }
    }
    /// The editor's body font (the text view's `font` reflects whatever styles index 0).
    var textFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular) {
        didSet { updateThickness() }
    }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private var font: NSFont {
        let size = max(9, textFont.pointSize * 0.8)
        return .monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    private func updateThickness() {
        let digits = max(3, String(lineIndex.lineCount).count)
        let width = CGFloat(digits) * (font.maximumAdvancement.width) + 16
        if abs(ruleThickness - width) > 0.5 { ruleThickness = width }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        let ns = textView.string as NSString
        let visible = textView.visibleRect
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let chars = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let caretLine = lineIndex.line(containing: textView.selectedRange().location)
        let origin = textView.textContainerOrigin

        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        let current: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]

        func draw(_ line: Int, fragment: NSRect) {
            let label = "\(line + 1)" as NSString
            let attributes = line == caretLine ? current : normal
            let size = label.size(withAttributes: attributes)
            let y = convert(NSPoint(x: 0, y: fragment.minY + origin.y), from: textView).y
            // Align with the first line's baseline area rather than the full (possibly tall) fragment.
            let lineHeight = layoutManager.defaultLineHeight(for: textFont)
            let point = NSPoint(x: ruleThickness - size.width - 8, y: y + max(0, (min(fragment.height, lineHeight * 1.15) - size.height) / 2))
            label.draw(at: point, withAttributes: attributes)
        }

        var line = lineIndex.line(containing: chars.location)
        while line < lineIndex.lineCount {
            let start = lineIndex.start(ofLine: line)
            if start > NSMaxRange(chars) { break }
            if start >= ns.length {
                // Trailing empty line after the final newline.
                if ns.length == 0 || ns.character(at: ns.length - 1) == 0x0A {
                    draw(line, fragment: layoutManager.extraLineFragmentRect)
                }
                break
            }
            let glyph = layoutManager.glyphIndexForCharacter(at: start)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            draw(line, fragment: fragment)
            line += 1
        }
    }
}
