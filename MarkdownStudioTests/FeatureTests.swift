import Foundation
import Testing
@testable import Markdown_Studio

private func caret(_ marked: String) -> (String, NSRange) {
    let ns = marked as NSString
    let r = ns.range(of: "|")
    return (ns.replacingCharacters(in: r, with: ""), NSRange(location: r.location, length: 0))
}

private func show(_ text: String, _ edit: TextEdit?) -> String? {
    guard let edit else { return nil }
    let result = edit.applied(to: text) as NSString
    return result.replacingCharacters(in: NSRange(location: edit.selection.location, length: 0), with: "|")
}

struct MoveLinesTests {
    private func move(_ marked: String, up: Bool) -> String? {
        let (text, sel) = caret(marked)
        return show(text, MarkdownEditing.moveLines(text, selection: sel, up: up))
    }

    @Test func movesSingleLines() {
        #expect(move("one\ntwo\nth|ree", up: true) == "one\nth|ree\ntwo")
        #expect(move("o|ne\ntwo\nthree", up: false) == "two\no|ne\nthree")
        #expect(move("o|ne\ntwo", up: true) == nil)
        #expect(move("one\ntw|o\n", up: false) == nil)
    }

    @Test func listItemsMoveWithChildren() {
        let text = "- a|\n    - a1\n- b\n    - b1"
        #expect(move(text, up: false) == "- b\n    - b1\n- a|\n    - a1")
        #expect(move("- a\n    - a1\n- b|\n    - b1", up: true) == "- b|\n    - b1\n- a\n    - a1")
    }

    @Test func duplicatesLines() {
        let (text, sel) = caret("one\ntw|o\nthree")
        #expect(show(text, MarkdownEditing.duplicateLines(text, selection: sel)) == "one\ntwo\ntw|o\nthree")
    }
}

struct RenumberTests {
    @Test func renumbersFromFirstNumber() {
        let text = "1. Plan\n2. Draft\n4. Edit\n3. Ship"
        #expect(MarkdownEditing.renumberList(text, line: 2)?.applied(to: text) == "1. Plan\n2. Draft\n3. Edit\n4. Ship")
        let fromFive = "5) a\n9) b"
        #expect(MarkdownEditing.renumberList(fromFive, line: 0)?.applied(to: fromFive) == "5) a\n6) b")
    }

    @Test func leavesOtherLevelsAlone() {
        let text = "1. a\n    1. x\n    5. y\n3. b"
        #expect(MarkdownEditing.renumberList(text, line: 3)?.applied(to: text) == "1. a\n    1. x\n    5. y\n2. b")
        #expect(MarkdownEditing.renumberList(text, line: 2)?.applied(to: text) == "1. a\n    1. x\n    2. y\n3. b")
    }

    @Test func returnsNilWhenSequentialOrNotAList() {
        #expect(MarkdownEditing.renumberList("1. a\n2. b", line: 1) == nil)
        #expect(MarkdownEditing.renumberList("1. a\nParagraph", line: 1) == nil)
    }

    @Test func keepsCaretOnItsText() {
        let text = "9. a\n9. b\n9. c"
        let caretLocation = (text as NSString).range(of: "c").location
        let edit = MarkdownEditing.renumberList(text, line: 2, selection: NSRange(location: caretLocation, length: 0))
        #expect(show(text, edit) == "9. a\n10. b\n11. |c")
    }
}

struct TableOfContentsTests {
    @Test func slugsMatchRenderer() {
        #expect(HeadingSlug.slugify("Hello, World!") == "hello-world")
        #expect(HeadingSlug.slugify("Café & Crème") == "café-crème")
        #expect(HeadingSlug.slugify("Ünïcode—dash") == "ünïcodedash")
        #expect(HeadingSlug.uniqueIDs([("Intro", nil), ("Intro", nil), ("X", "custom")]) == ["intro", "intro-1", "custom"])
    }

    @Test func insertsNestedLinks() throws {
        let text = "# Title\n\n## Install\n### macOS\n## Usage {#use}\n"
        let edit = try #require(TableOfContents.insert(text, selection: NSRange(location: 8, length: 0)))
        let result = edit.applied(to: text)
        #expect(result.contains("<!-- toc -->\n- [Install](#install)\n  - [macOS](#macos)\n- [Usage](#use)\n<!-- /toc -->"))
    }

    @Test func updatesWhenHeadingsChange() throws {
        let text = "<!-- toc -->\n- [Old](#old)\n<!-- /toc -->\n\n## New name\n"
        let edit = try #require(TableOfContents.update(text))
        #expect(edit.applied(to: text) == "<!-- toc -->\n- [New name](#new-name)\n<!-- /toc -->\n\n## New name\n")
        #expect(TableOfContents.update(edit.applied(to: text)) == nil)
    }
}

struct WritingGoalTests {
    @Test func readsAndEditsFrontMatterGoal() throws {
        let text = "---\ntitle: x\ngoal: 1500\n---\n# Hi"
        #expect(WritingGoal.frontMatterGoal(in: text) == 1500)
        let edit = try #require(WritingGoal.frontMatterEdit(in: text, goal: 800))
        #expect(edit.applied(to: text) == "---\ntitle: x\ngoal: 800\n---\n# Hi")
        #expect(WritingGoal.frontMatterEdit(in: text, goal: nil)?.applied(to: text) == "---\ntitle: x\n---\n# Hi")
        #expect(WritingGoal.frontMatterGoal(in: "# No front matter\ngoal: 5") == nil)
    }
}

struct TemplateTests {
    @Test func fillsPlaceholders() throws {
        let template = DocumentTemplate(name: "Notes", text: "# {{title}} {{date}} {{year}}", isBuiltIn: true)
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-13T12:00:00Z"))
        #expect(template.filled(now: date).hasPrefix("# Notes 2026-10-1"))
        #expect(TemplateLibrary.builtIn.map(\.name) == ["README", "Meeting Notes", "Blog Post", "Changelog"])
    }
}

struct DocumentCheckerTests {
    private let files = DocumentChecker.FileSystem(
        fileExists: { $0.path == "/docs/img/dashboard.png" || $0.path == "/docs/guide.md" },
        filesInDirectory: { $0.path == "/docs/img" ? ["dashboard.png", "logo.svg"] : ["guide.md"] }
    )
    private let folder = URL(filePath: "/docs/")

    private func messages(_ text: String) -> [String] {
        DocumentChecker.check(text, documentDirectory: folder, fileSystem: files).map(\.message)
    }

    @Test func findsMissingFilesWithSuggestion() throws {
        let text = "![Dash](img/dashbord.png) [ok](guide.md) [web](https://x.y/z.png)"
        let problems = DocumentChecker.check(text, documentDirectory: folder, fileSystem: files)
        #expect(problems.map(\.message) == ["Image not found: img/dashbord.png"])
        let fix = try #require(problems.first?.fix)
        #expect(fix.edit.applied(to: text) == "![Dash](img/dashboard.png) [ok](guide.md) [web](https://x.y/z.png)")
    }

    @Test func findsUnknownAnchors() throws {
        let text = "## Installation\nSee [setup](#instalation) and [ok](#installation)."
        let problems = DocumentChecker.check(text, documentDirectory: folder, fileSystem: files)
        #expect(problems.count == 1)
        #expect(problems[0].message.contains("Did you mean “installation”"))
        #expect(try #require(problems[0].fix).edit.applied(to: text).contains("[setup](#installation)"))
    }

    @Test func checksFootnotesAndReferences() {
        let result = messages("Text[^1] and [link][missing].\n\n[^2]: unused\n[known]: https://x.y\n[a][known]")
        #expect(result.contains("Footnote [^1] has no definition"))
        #expect(result.contains("Footnote [^2] is never referenced"))
        #expect(result.contains("No link definition for [missing]"))
        #expect(!result.contains { $0.contains("[known]") })
    }

    @Test func checksHeadingStructure() {
        let result = messages("# A\n### C\n## B\n## B")
        #expect(result.contains("Heading jumps from H1 to H3"))
        #expect(result.contains { $0.hasPrefix("Duplicate heading “B”") })
    }

    @Test func ignoresCode() {
        #expect(messages("```\n[x](missing.md)\n```\n`[y](#nope)`\n<!-- [z](#nope) -->").isEmpty)
    }

    @Test func untitledDocumentsSkipFileChecks() {
        #expect(DocumentChecker.check("![a](nope.png)", documentDirectory: nil, fileSystem: files).isEmpty)
    }
}
