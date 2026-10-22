import Foundation

extension MarkdownTextView {
    /// HTML with real document structure. Code editors such as VS Code put
    /// only styled <div>/<span> on the clipboard; that stays plain text.
    nonisolated static func isRichHTML(_ html: String) -> Bool {
        html.range(of: "<(h[1-6]|p|ul|ol|li|a|strong|b|em|i|table|blockquote|pre|code|img|del|s|mark)[\\s>]",
                   options: [.regularExpression, .caseInsensitive]) != nil
    }
}
