import Foundation
import Testing
@testable import Markdown_Studio

/// Applies an edit and renders the selection as `|` (caret) or `[…]` (range).
private func run(_ text: String, _ selection: NSRange, _ edit: (String, NSRange) -> TextEdit?) -> String? {
    guard let result = edit(text, selection) else { return nil }
    let ns = result.applied(to: text) as NSString
    let sel = result.selection
    if sel.length == 0 { return ns.replacingCharacters(in: NSRange(location: sel.location, length: 0), with: "|") }
    let marked = ns.replacingCharacters(in: NSRange(location: NSMaxRange(sel), length: 0), with: "]")
    return (marked as NSString).replacingCharacters(in: NSRange(location: sel.location, length: 0), with: "[")
}

/// Parses `|` / `[…]` markers out of a test string.
private func parse(_ marked: String) -> (String, NSRange) {
    let ns = marked as NSString
    let caret = ns.range(of: "|")
    if caret.location != NSNotFound {
        return (ns.replacingCharacters(in: caret, with: ""), NSRange(location: caret.location, length: 0))
    }
    let open = ns.range(of: "[[")
    let close = ns.range(of: "]]")
    let text = ns.replacingCharacters(in: close, with: "") as NSString
    return (text.replacingCharacters(in: open, with: ""), NSRange(location: open.location, length: close.location - open.location - 2))
}

private func apply(_ marked: String, _ edit: (String, NSRange) -> TextEdit?) -> String? {
    let (text, selection) = parse(marked)
    return run(text, selection, edit)
}

struct InlineFormattingTests {
    @Test func boldWrapsSelection() {
        #expect(apply("make [[this]] bold") { MarkdownEditing.toggleWrap($0, selection: $1, marker: "**") } == "make **[this]** bold")
    }

    @Test func boldUnwrapsWhenAlreadyBold() {
        #expect(apply("make **[[this]]** bold") { MarkdownEditing.toggleWrap($0, selection: $1, marker: "**") } == "make [this] bold")
        #expect(apply("make [[**this**]] bold") { MarkdownEditing.toggleWrap($0, selection: $1, marker: "**") } == "make [this] bold")
    }

    @Test func boldUsesWordUnderCaret() {
        #expect(apply("make th|is bold") { MarkdownEditing.toggleWrap($0, selection: $1, marker: "**") } == "make **[this]** bold")
    }

    @Test func emptySelectionInsertsPair() {
        #expect(apply("a | b") { MarkdownEditing.toggleWrap($0, selection: $1, marker: "`") } == "a `|` b")
    }

    @Test func italicInsideBoldAddsItalic() {
        #expect(apply("**[[word]]**") { MarkdownEditing.toggleWrap($0, selection: $1, marker: "*") } == "***[word]***")
        #expect(apply("***[[word]]***") { MarkdownEditing.toggleWrap($0, selection: $1, marker: "*") } == "**[word]**")
        #expect(apply("***[[word]]***") { MarkdownEditing.toggleWrap($0, selection: $1, marker: "**") } == "*[word]*")
    }

    @Test func strikethroughAndHighlight() {
        #expect(apply("[[gone]]") { MarkdownEditing.toggleWrap($0, selection: $1, marker: "~~") } == "~~[gone]~~")
        #expect(apply("==[[mark]]==") { MarkdownEditing.toggleWrap($0, selection: $1, marker: "==") } == "[mark]")
    }
}

struct LinkTests {
    @Test func linkAroundSelectionPutsCaretInURL() {
        #expect(apply("see [[docs]] here") { MarkdownEditing.insertLink($0, selection: $1) } == "see [docs](|) here")
    }

    @Test func linkUsesClipboardURL() {
        #expect(apply("[[docs]]") { MarkdownEditing.insertLink($0, selection: $1, clipboardURL: "https://example.com") }
                == "[docs](https://example.com)|")
    }

    @Test func selectedURLBecomesTarget() {
        #expect(apply("[[https://example.com]]") { MarkdownEditing.insertLink($0, selection: $1) } == "[|](https://example.com)")
    }

    @Test func imageSyntax() {
        #expect(apply("|") { MarkdownEditing.insertLink($0, selection: $1, image: true) } == "![|]()")
    }
}

struct LinePrefixTests {
    @Test func setHeadingReplacesExistingLevel() {
        #expect(apply("## Ti|tle") { MarkdownEditing.setHeading($0, selection: $1, level: 3) } == "### Ti|tle")
        #expect(apply("## Ti|tle") { MarkdownEditing.setHeading($0, selection: $1, level: 0) } == "Ti|tle")
    }

    @Test func cycleHeading() {
        #expect(apply("Title|") { MarkdownEditing.cycleHeading($0, selection: $1) } == "# Title|")
        #expect(apply("###### Title|") { MarkdownEditing.cycleHeading($0, selection: $1) } == "Title|")
    }

    @Test func blockquoteToggles() {
        #expect(apply("[[one\ntwo]]") { MarkdownEditing.toggleBlockquote($0, selection: $1) } == "[> one\n> two]")
        #expect(apply("[[> one\n> two]]") { MarkdownEditing.toggleBlockquote($0, selection: $1) } == "[one\ntwo]")
    }

    @Test func listsConvertBetweenKinds() {
        #expect(apply("[[a\nb]]") { MarkdownEditing.toggleList($0, selection: $1, kind: .bullet) } == "[- a\n- b]")
        #expect(apply("[[- a\n- b]]") { MarkdownEditing.toggleList($0, selection: $1, kind: .numbered) } == "[1. a\n2. b]")
        #expect(apply("[[1. a\n2. b]]") { MarkdownEditing.toggleList($0, selection: $1, kind: .task) } == "[- [ ] a\n- [ ] b]")
        #expect(apply("[[- [ ] a\n- [ ] b]]") { MarkdownEditing.toggleList($0, selection: $1, kind: .task) } == "[a\nb]")
    }

    @Test func indentAndOutdent() {
        #expect(apply("- it|em") { MarkdownEditing.indent($0, selection: $1) } == "    - it|em")
        #expect(apply("    - it|em") { MarkdownEditing.outdent($0, selection: $1) } == "- it|em")
    }

    @Test func codeBlockWrapsLines() {
        #expect(apply("[[let x = 1]]") { MarkdownEditing.toggleCodeBlock($0, selection: $1) } == "```|\nlet x = 1\n```")
        #expect(apply("|") { MarkdownEditing.toggleCodeBlock($0, selection: $1) } == "```|\n\n```")
    }
}

struct SmartListTests {
    private func newline(_ marked: String) -> String? {
        apply(marked) { MarkdownEditing.newline($0, selection: $1) }
    }

    @Test func continuesBullets() {
        #expect(newline("- one|") == "- one\n- |")
        #expect(newline("  * one|") == "  * one\n  * |")
    }

    @Test func incrementsNumbers() {
        #expect(newline("9. nine|") == "9. nine\n10. |")
        #expect(newline("1) one|") == "1) one\n2) |")
    }

    @Test func continuesTasksUnchecked() {
        #expect(newline("- [x] done|") == "- [x] done\n- [ ] |")
    }

    @Test func continuesBlockquotes() {
        #expect(newline("> quote|") == "> quote\n> |")
    }

    @Test func emptyItemEndsList() {
        #expect(newline("- one\n- |") == "- one\n|")
        #expect(newline("- [ ] |") == "|")
    }

    @Test func plainLinesAreNotHandled() {
        #expect(newline("hello|") == nil)
        #expect(newline("|- item") == nil)
    }
}

struct TaskToggleTests {
    @Test func togglesCheckbox() {
        let text = "# Tasks\n- [ ] one\n- [x] two"
        #expect(MarkdownEditing.toggleTask(text, line: 1)?.applied(to: text) == "# Tasks\n- [x] one\n- [x] two")
        #expect(MarkdownEditing.toggleTask(text, line: 2)?.applied(to: text) == "# Tasks\n- [ ] one\n- [ ] two")
    }

    @Test func togglesNestedAndQuotedTasks() {
        #expect(MarkdownEditing.toggleTask("3. - [ ] nested", line: 0)?.replacement == "x")
        #expect(MarkdownEditing.toggleTask("> - [X] quoted", line: 0)?.replacement == " ")
    }

    @Test func ignoresNonTasks() {
        #expect(MarkdownEditing.toggleTask("- plain item", line: 0) == nil)
        #expect(MarkdownEditing.toggleTask("one line", line: 5) == nil)
    }
}
