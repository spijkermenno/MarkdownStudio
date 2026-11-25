import SwiftUI

/// Quick reference of the syntax from markdownguide.org.
struct CheatSheetView: View {
    private struct Entry: Identifiable {
        let element: String
        let syntax: String
        var id: String { element }
    }

    private let basic: [Entry] = [
        Entry(element: "Heading", syntax: "# H1\n## H2\n### H3"),
        Entry(element: "Bold", syntax: "**bold text**"),
        Entry(element: "Italic", syntax: "*italicized text*"),
        Entry(element: "Blockquote", syntax: "> blockquote"),
        Entry(element: "Ordered List", syntax: "1. First item\n2. Second item\n3. Third item"),
        Entry(element: "Unordered List", syntax: "- First item\n- Second item\n- Third item"),
        Entry(element: "Code", syntax: "`code`"),
        Entry(element: "Horizontal Rule", syntax: "---"),
        Entry(element: "Link", syntax: "[title](https://www.example.com)"),
        Entry(element: "Image", syntax: "![alt text](image.jpg)"),
        Entry(element: "Line Break", syntax: "End a line with two spaces  \nor use <br>"),
        Entry(element: "Escaping", syntax: "\\* not a list item"),
    ]

    private let extended: [Entry] = [
        Entry(element: "Table", syntax: "| Syntax | Description |\n| :--- | ---: |\n| Header | Title |"),
        Entry(element: "Fenced Code Block", syntax: "```json\n{ \"firstName\": \"John\" }\n```"),
        Entry(element: "Footnote", syntax: "Here's a sentence with a footnote. [^1]\n\n[^1]: This is the footnote."),
        Entry(element: "Heading ID", syntax: "### My Great Heading {#custom-id}"),
        Entry(element: "Definition List", syntax: "term\n: definition"),
        Entry(element: "Strikethrough", syntax: "~~The world is flat.~~"),
        Entry(element: "Task List", syntax: "- [x] Write the press release\n- [ ] Update the website"),
        Entry(element: "Emoji", syntax: "That is so funny! :joy:"),
        Entry(element: "Highlight", syntax: "I need to highlight these ==very important words==."),
        Entry(element: "Subscript", syntax: "H~2~O"),
        Entry(element: "Superscript", syntax: "X^2^"),
        Entry(element: "Automatic URL", syntax: "https://www.example.com"),
        Entry(element: "Math (extra)", syntax: "$E = mc^2$ and $$\\sum_{i=1}^n i$$"),
        Entry(element: "Diagram (extra)", syntax: "```mermaid\ngraph LR; A-->B\n```"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("Basic Syntax", basic)
                section("Extended Syntax", extended)
                Link("Full reference at markdownguide.org →", destination: URL(string: "https://www.markdownguide.org/cheat-sheet/")!)
            }
            .padding(24)
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 400)
        #endif
    }

    private func section(_ title: String, _ entries: [Entry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title2.bold())
            Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 10) {
                ForEach(entries) { entry in
                    GridRow {
                        Text(entry.element)
                            .fontWeight(.medium)
                            .frame(width: 140, alignment: .leading)
                        Text(entry.syntax)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Divider()
                }
            }
        }
    }
}
