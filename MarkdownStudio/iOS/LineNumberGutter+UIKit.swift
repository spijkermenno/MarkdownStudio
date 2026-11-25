#if os(iOS)
import UIKit

/// Draws source line numbers beside the editor. It sits inside the text view
/// and follows the visible area, so it only draws the lines on screen.
final class LineNumberGutterView: UIView {
    private weak var textView: UITextView?
    var lineIndex = LineIndex("") {
        didSet { setNeedsDisplay() }
    }
    /// The editor's body font.
    var textFont: UIFont = .monospacedSystemFont(ofSize: 14, weight: .regular) {
        didSet { setNeedsDisplay() }
    }

    init(textView: UITextView) {
        self.textView = textView
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        isUserInteractionEnabled = false
        // VoiceOver reads the line from the status bar instead.
        isAccessibilityElement = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var font: UIFont {
        .monospacedDigitSystemFont(ofSize: max(9, textFont.pointSize * 0.8), weight: .regular)
    }

    /// Wide enough for the largest line number (at least three digits).
    var width: CGFloat {
        let digits = max(3, String(lineIndex.lineCount).count)
        let digit = ("8" as NSString).size(withAttributes: [.font: font]).width
        return (CGFloat(digits) * digit + 16).rounded(.up)
    }

    /// Keeps the gutter over the visible part of the text view.
    func follow() {
        guard let textView else { return }
        let frame = CGRect(x: textView.contentOffset.x, y: textView.contentOffset.y, width: width, height: textView.bounds.height)
        if self.frame != frame { self.frame = frame }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let textView, let container = textView.textContainer as NSTextContainer?,
              let layoutManager = container.layoutManager else { return }
        let ns = textView.text as NSString
        let inset = textView.textContainerInset
        // The visible area in text-container coordinates.
        let visible = CGRect(x: 0, y: textView.contentOffset.y - inset.top, width: container.size.width, height: bounds.height)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let chars = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let caretLine = lineIndex.line(containing: textView.selectedRange.location)

        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: MarkdownHighlighter.Colors.lineNumber]
        let current: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label]
        let lineHeight = textFont.lineHeight

        func draw(_ line: Int, fragment: CGRect) {
            let label = "\(line + 1)" as NSString
            let attributes = line == caretLine ? current : normal
            let size = label.size(withAttributes: attributes)
            let y = fragment.minY + inset.top - textView.contentOffset.y
            // Align with the first line of a wrapped paragraph rather than the whole fragment.
            label.draw(at: CGPoint(x: bounds.width - size.width - 8,
                                   y: y + max(0, (min(fragment.height, lineHeight * 1.15) - size.height) / 2)),
                       withAttributes: attributes)
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
            draw(line, fragment: layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil))
            line += 1
        }
    }
}
#endif
