import SwiftUI

/// Optional row of formatting buttons above the editor.
struct FormattingBar: View {
    let session: DocumentSession

    struct Item: Identifiable {
        let command: FormatCommand
        let title: String
        let symbol: String
        let shortcut: String
        var id: String { title }
    }

    static let groups: [[Item]] = [
        [
            Item(command: .bold, title: "Bold", symbol: "bold", shortcut: "⌘B"),
            Item(command: .italic, title: "Italic", symbol: "italic", shortcut: "⌘I"),
            Item(command: .strikethrough, title: "Strikethrough", symbol: "strikethrough", shortcut: "⇧⌘X"),
            Item(command: .highlight, title: "Highlight", symbol: "highlighter", shortcut: "⇧⌘H"),
            Item(command: .inlineCode, title: "Inline Code", symbol: "chevron.left.forwardslash.chevron.right", shortcut: "⇧⌘K"),
        ],
        [
            Item(command: .cycleHeading, title: "Heading", symbol: "number", shortcut: "⌘/"),
            Item(command: .blockquote, title: "Blockquote", symbol: "text.quote", shortcut: "⌘'"),
            Item(command: .bulletList, title: "Bulleted List", symbol: "list.bullet", shortcut: "⇧⌘8"),
            Item(command: .numberedList, title: "Numbered List", symbol: "list.number", shortcut: "⇧⌘7"),
            Item(command: .taskList, title: "Task List", symbol: "checklist", shortcut: "⇧⌘9"),
        ],
        [
            Item(command: .link, title: "Link", symbol: "link", shortcut: "⌘K"),
            Item(command: .image, title: "Image", symbol: "photo", shortcut: "⇧⌘I"),
            Item(command: .codeBlock, title: "Code Block", symbol: "curlybraces", shortcut: "⌥⌘K"),
            Item(command: .table, title: "Table", symbol: "tablecells", shortcut: ""),
            Item(command: .tableOfContents, title: "Table of Contents", symbol: "list.bullet.rectangle", shortcut: ""),
            Item(command: .horizontalRule, title: "Horizontal Rule", symbol: "minus", shortcut: ""),
        ],
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.groups.indices, id: \.self) { index in
                if index > 0 {
                    Divider().frame(height: 16).padding(.horizontal, 6)
                }
                ForEach(Self.groups[index]) { item in
                    Button {
                        session.perform(item.command)
                    } label: {
                        // At least 24 × 24 points (WCAG 2.5.8), clickable across the whole frame.
                        Image(systemName: item.symbol)
                            .frame(width: 28, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(item.shortcut.isEmpty ? item.title : "\(item.title) (\(item.shortcut))")
                    .accessibilityLabel(item.title)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(.bar)
    }
}
