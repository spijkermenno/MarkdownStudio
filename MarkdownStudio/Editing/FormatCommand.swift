import Foundation

enum FormatCommand: Hashable {
    case bold, italic, strikethrough, highlight, inlineCode
    case link, image
    case heading(Int), cycleHeading
    case blockquote, bulletList, numberedList, taskList
    case codeBlock, horizontalRule, table, formatTable
    case indent, outdent
    case moveLinesUp, moveLinesDown, duplicateLines, renumberList, tableOfContents

    var actionName: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .highlight: "Highlight"
        case .inlineCode: "Code"
        case .link: "Insert Link"
        case .image: "Insert Image"
        case .heading(let level): level == 0 ? "Paragraph" : "Heading \(level)"
        case .cycleHeading: "Heading"
        case .blockquote: "Blockquote"
        case .bulletList: "Bulleted List"
        case .numberedList: "Numbered List"
        case .taskList: "Task List"
        case .codeBlock: "Code Block"
        case .horizontalRule: "Horizontal Rule"
        case .table: "Insert Table"
        case .formatTable: "Format Table"
        case .indent: "Indent"
        case .outdent: "Outdent"
        case .moveLinesUp: "Move Line Up"
        case .moveLinesDown: "Move Line Down"
        case .duplicateLines: "Duplicate Line"
        case .renumberList: "Renumber List"
        case .tableOfContents: "Table of Contents"
        }
    }
}
