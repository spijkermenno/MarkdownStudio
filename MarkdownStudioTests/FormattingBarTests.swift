import AppKit
import Foundation
import Testing
@testable import Markdown_Studio

/// Every formatting-bar button must do something, also on an empty line.
@MainActor
struct FormattingBarTests {
    private var commands: [FormatCommand] { FormattingBar.groups.flatMap { $0.map(\.command) } }

    private func run(_ command: FormatCommand, text: String, caret: Int) -> String? {
        let controller = EditorController(text: text)
        controller.textView.setSelectedRange(NSRange(location: caret, length: 0))
        controller.perform(command)
        return controller.text
    }

    @Test func everyButtonWorksInAnEmptyDocument() {
        for command in commands {
            let result = run(command, text: "", caret: 0)
            #expect(result != "", "\(command.actionName) did nothing in an empty document")
        }
    }

    @Test func everyButtonWorksOnABlankLineBetweenText() {
        let text = "# Title\n\nFirst paragraph.\n\n\n\nLast paragraph."
        let blankLine = (text as NSString).range(of: "\n\n\n").location + 2
        for command in commands {
            let result = run(command, text: text, caret: blankLine)
            #expect(result != text, "\(command.actionName) did nothing on a blank line")
        }
    }

    @Test func everyButtonWorksOnALineWithText() {
        let text = "# Title\n\nSome words here\n"
        let caret = (text as NSString).range(of: "words").location + 2
        for command in commands {
            let result = run(command, text: text, caret: caret)
            #expect(result != text, "\(command.actionName) did nothing on a line with text")
        }
    }

    @Test func listButtonsOnEmptyLineStartAList() {
        #expect(run(.bulletList, text: "", caret: 0) == "- ")
        #expect(run(.numberedList, text: "", caret: 0) == "1. ")
        #expect(run(.taskList, text: "", caret: 0) == "- [ ] ")
        #expect(run(.blockquote, text: "", caret: 0) == "> ")
        // Pressing the button again removes the marker.
        #expect(run(.bulletList, text: "- ", caret: 2) == "")
    }

    @Test func tableOfContentsButtonIsInTheBar() {
        #expect(commands.contains(.tableOfContents))
    }
}
