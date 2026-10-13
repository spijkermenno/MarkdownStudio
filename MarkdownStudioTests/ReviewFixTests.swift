import Foundation
import JavaScriptCore
import Testing
@testable import Markdown_Studio

/// Regression tests for bugs found in the code review.
@MainActor
struct ReviewFixTests {
    /// Swift heading anchors (TOC, autocomplete, document check) must equal the preview's IDs.
    @Test func headingAnchorsMatchThePreview() throws {
        let context = try #require(JSContext())
        let web = PreviewSchemeHandler.webRoot
        for file in ["vendor/markdown-it.min.js", "vendor/markdown-it-footnote.min.js", "vendor/markdown-it-deflist.min.js",
                     "vendor/markdown-it-mark.min.js", "vendor/markdown-it-sub.min.js", "vendor/markdown-it-sup.min.js",
                     "vendor/markdown-it-emoji.min.js", "render.js"] {
            context.evaluateScript(try String(contentsOf: web.appending(path: file), encoding: .utf8))
        }
        let markdown = """
        # Meeting at 10:30:00
        ## ![logo](l.png) Project
        ## Tom &amp; Jerry
        ## Untitled
        ## Party :tada: time
        ## **Bold** and `code` with [a link](x)
        ## Café & Crème
        ## Intro
        ## Intro
        ### Custom {#my-id}
        """
        let renderer = try #require(context.evaluateScript("MDStudio.createRenderer({math: false, hljs: null})"))
        let html = try #require(renderer.invokeMethod("render", withArguments: [markdown])?.forProperty("html")?.toString())
        let regex = try NSRegularExpression(pattern: #"<h\d id="([^"]+)""#)
        let previewIDs = regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).map { (html as NSString).substring(with: $0.range(at: 1)) }
        #expect(OutlineParser.parse(markdown).map(\.anchor) == previewIDs)
    }

    @Test func tableOfContentsIgnoresMarkersInCodeBlocks() {
        let text = "```markdown\n<!-- toc -->\n<!-- /toc -->\n```\n\n## Heading\n"
        #expect(TableOfContents.markers(in: text) == nil)
        #expect(TableOfContents.update(text) == nil)
    }

    @Test func checkerHandlesWindowsLineEndingsAfterCodeBlocks() {
        let text = "```\r\ncode 🎉\r\n```\r\n[ref]: https://example.com\r\n\r\nSee [a][ref].\r\n"
        #expect(DocumentChecker.check(text, documentDirectory: nil).isEmpty)
    }

    @Test func renumberingLeavesRepeatedNumbersAndCodeAlone() {
        #expect(MarkdownEditing.renumberList("1. a\n1. b\n1. c", line: 2) == nil)
        #expect(MarkdownEditing.renumberList("```\n1. a\n5. b\n```", line: 2) == nil)
        let lazy = "1. a\n1. b"
        #expect(MarkdownEditing.newline(lazy, selection: NSRange(location: lazy.utf16Length, length: 0))?.replacement == "\n1. ")
    }

    @Test func quickFixUsesTheCurrentText() {
        let session = DocumentSession(text: "Text[^1]", fileURL: nil, viewMode: .split, splitOrientation: .horizontal)
        // A stale problem whose fix points past the end of the (now shorter) text.
        let stale = DocumentProblem(range: NSRange(location: 4, length: 4), line: 0,
                                    message: "Footnote [^1] has no definition", severity: .warning,
                                    fix: .init(title: "Add definition", edit: TextEdit(range: NSRange(location: 500, length: 0),
                                                                                       replacement: "x", selection: NSRange(location: 501, length: 0))))
        session.fix(stale)
        #expect(session.text.hasSuffix("[^1]: "))
    }

    @Test func pastedLineBreaksStayHardBreaks() async throws {
        let preview = PreviewController()
        let markdown = try #require(await preview.markdown(fromHTML: "<p>Line one<br>Line two</p>"))
        #expect(markdown == "Line one  \nLine two")
    }
}
